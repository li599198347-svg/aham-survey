import Foundation
import Accelerate
import CoreML

/// 说话人嵌入向量引擎
///
/// 优先使用 ECAPA-TDNN CoreML 神经网络模型 (需要将 ECAPA_TDNN.mlpackage
/// 拖入 Xcode 项目，target membership: Aham)；模型不存在时自动降级为
/// Mel-Fbank 统计特征。
///
/// 转换脚本: Aham/convert_ecapa.py
@MainActor
final class SpeakerEmbedding {

    // MARK: - Constants

    static let embeddingDim   = 192
    static let framesPerChunk = 300      // 3 s @ 10 ms hop

    /// 匹配阈值 — ECAPA-TDNN 0.75，降级 Mel-Fbank 0.82
    static var matchThreshold: Float {
        Bundle.main.url(forResource: "ECAPA_TDNN", withExtension: "mlpackage") != nil
            ? 0.75 : 0.82
    }

    // MARK: - Mel-Fbank 参数 (16 kHz)

    private let fftSize     = 512
    private let hopLength   = 160        // 10 ms @ 16 kHz
    private let numMelBins  = 80
    private let preemphasis: Float = 0.97
    private let melFilterBank: [[Float]]

    // MARK: - CoreML

    private var mlModel: MLModel?

    var isModelAvailable: Bool { mlModel != nil }

    init() {
        melFilterBank = Self.createMelFilterBank(
            numFilters: 80, fftSize: 512, sampleRate: 16000
        )
        if let url = Bundle.main.url(forResource: "ECAPA_TDNN",
                                      withExtension: "mlpackage") {
            mlModel = try? MLModel(contentsOf: url)
            if mlModel != nil {
                print("[SpeakerEmbedding] ECAPA-TDNN CoreML model loaded")
            }
        }
    }

    // MARK: - 公开 API

    /// 从任意采样率的 PCM 样本提取声纹嵌入向量
    ///
    /// - Parameters:
    ///   - audioSamples:      原始 PCM float32 样本
    ///   - captureSampleRate: 录制时的采样率 (如 48000)，内部自动降采样到 16 kHz
    func extractEmbedding(from audioSamples: [Float],
                          captureSampleRate: Double = 16000) -> [Float] {
        let samples16k = resampleTo16kHz(audioSamples, fromRate: captureSampleRate)
        guard !samples16k.isEmpty else {
            return [Float](repeating: 0, count: Self.embeddingDim)
        }

        // 按 300 帧窗口 + 50% 重叠分块处理
        let chunkSamples = Self.framesPerChunk * hopLength + fftSize   // ~48512 @ 16 kHz
        let hopSamples   = (Self.framesPerChunk / 2) * hopLength       // 150 帧步进

        var chunkEmbeddings: [[Float]] = []

        if samples16k.count >= chunkSamples {
            var start = 0
            while start + chunkSamples <= samples16k.count {
                let chunk = Array(samples16k[start ..< start + chunkSamples])
                chunkEmbeddings.append(processChunk(chunk))
                start += hopSamples
            }
        }

        // 音频不足一个完整窗口时直接处理全部
        if chunkEmbeddings.isEmpty {
            chunkEmbeddings.append(processChunk(samples16k))
        }

        return Self.averageEmbeddings(chunkEmbeddings)
    }

    // MARK: - 静态工具

    /// 计算两个嵌入向量的余弦相似度
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        vDSP_dotpr(a, 1, b, 1, &dot,   vDSP_Length(a.count))
        vDSP_dotpr(a, 1, a, 1, &normA, vDSP_Length(a.count))
        vDSP_dotpr(b, 1, b, 1, &normB, vDSP_Length(b.count))

        let denom = sqrt(normA) * sqrt(normB)
        guard denom > 0 else { return 0 }
        return dot / denom
    }

    /// 合并多个嵌入向量 (平均后 L2 归一化)
    static func averageEmbeddings(_ embeddings: [[Float]]) -> [Float] {
        guard let first = embeddings.first else { return [] }
        guard embeddings.count > 1 else { return first }

        var result = [Float](repeating: 0, count: first.count)
        for e in embeddings {
            vDSP_vadd(result, 1, e, 1, &result, 1, vDSP_Length(first.count))
        }
        var count = Float(embeddings.count)
        vDSP_vsdiv(result, 1, &count, &result, 1, vDSP_Length(first.count))
        return l2Normalize(result)
    }

    // MARK: - 分块处理

    private func processChunk(_ samples: [Float]) -> [Float] {
        let emphasized  = applyPreemphasis(samples)
        let powerSpec   = computePowerSpectrum(emphasized)
        let melFeatures = applyMelFilterBank(powerSpec)

        if let model = mlModel, let result = runCoreML(melFeatures, model: model) {
            return result
        }
        return poolAndNormalize(melFeatures)
    }

    // MARK: - CoreML 推理

    private func runCoreML(_ frames: [[Float]], model: MLModel) -> [Float]? {
        let T = Self.framesPerChunk

        // Pad / trim to exactly T frames
        var padded = frames
        if padded.count < T {
            let zeros = [Float](repeating: 0, count: numMelBins)
            while padded.count < T { padded.append(zeros) }
        } else if padded.count > T {
            padded = Array(padded.prefix(T))
        }

        // Build MLMultiArray [1, T, 80]
        guard let mlArray = try? MLMultiArray(
            shape: [1, T as NSNumber, numMelBins as NSNumber],
            dataType: .float32
        ) else { return nil }

        let ptr = mlArray.dataPointer.bindMemory(to: Float.self,
                                                  capacity: T * numMelBins)
        for t in 0..<T {
            for c in 0..<numMelBins {
                ptr[t * numMelBins + c] = padded[t][c]
            }
        }

        guard
            let provider = try? MLDictionaryFeatureProvider(
                dictionary: ["fbank_features": mlArray]
            ),
            let output   = try? model.prediction(from: provider),
            let embArray = output.featureValue(for: "speaker_embedding")?.multiArrayValue
        else { return nil }

        // embArray may be [1,192] or [1,1,192] depending on model version
        let totalCount = embArray.count
        guard totalCount >= Self.embeddingDim else { return nil }
        let offset = totalCount - Self.embeddingDim   // skip leading extra dims
        var embedding = [Float](repeating: 0, count: Self.embeddingDim)
        let embPtr = embArray.dataPointer.bindMemory(to: Float.self, capacity: totalCount)
        for i in 0..<Self.embeddingDim {
            embedding[i] = embPtr[offset + i]
        }
        return Self.l2Normalize(embedding)
    }

    // MARK: - 降采样 (任意率 → 16 kHz，线性插值)

    private func resampleTo16kHz(_ samples: [Float], fromRate: Double) -> [Float] {
        guard fromRate != 16000 else { return samples }
        let ratio    = fromRate / 16000.0
        let outCount = Int(Double(samples.count) / ratio)
        guard outCount > 0 else { return [] }

        var output = [Float](repeating: 0, count: outCount)
        for i in 0..<outCount {
            let srcPos = Double(i) * ratio
            let idx    = Int(srcPos)
            let frac   = Float(srcPos - Double(idx))
            let s0     = idx     < samples.count ? samples[idx]     : 0
            let s1     = idx + 1 < samples.count ? samples[idx + 1] : 0
            output[i]  = s0 + frac * (s1 - s0)
        }
        return output
    }

    // MARK: - 信号处理

    private func applyPreemphasis(_ signal: [Float]) -> [Float] {
        guard signal.count > 1 else { return signal }
        var result = [Float](repeating: 0, count: signal.count)
        result[0] = signal[0]
        for i in 1..<signal.count {
            result[i] = signal[i] - preemphasis * signal[i - 1]
        }
        return result
    }

    private func computePowerSpectrum(_ signal: [Float]) -> [[Float]] {
        let numFrames = max(0, (signal.count - fftSize) / hopLength + 1)
        guard numFrames > 0 else { return [] }

        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        let halfFFT = fftSize / 2 + 1
        var spectra = [[Float]]()
        spectra.reserveCapacity(numFrames)

        guard let fftSetup = vDSP_create_fftsetup(
            vDSP_Length(log2(Float(fftSize))), FFTRadix(kFFTRadix2)
        ) else { return [] }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        var realPart = [Float](repeating: 0, count: halfFFT)
        var imagPart = [Float](repeating: 0, count: halfFFT)

        for frame in 0..<numFrames {
            let start = frame * hopLength
            let end   = min(start + fftSize, signal.count)
            var frameSamples = [Float](repeating: 0, count: fftSize)
            frameSamples[0..<(end - start)] = signal[start..<end]
            vDSP_vmul(frameSamples, 1, window, 1, &frameSamples, 1, vDSP_Length(fftSize))

            frameSamples.withUnsafeMutableBufferPointer { buf in
                buf.baseAddress!.withMemoryRebound(to: DSPComplex.self,
                                                    capacity: halfFFT) { cx in
                    realPart.withUnsafeMutableBufferPointer { rBuf in
                        imagPart.withUnsafeMutableBufferPointer { iBuf in
                            var split = DSPSplitComplex(realp: rBuf.baseAddress!,
                                                        imagp: iBuf.baseAddress!)
                            vDSP_ctoz(cx, 2, &split, 1, vDSP_Length(halfFFT))
                            vDSP_fft_zrip(fftSetup, &split, 1,
                                          vDSP_Length(log2(Float(fftSize))),
                                          FFTDirection(FFT_FORWARD))
                        }
                    }
                }
            }

            var power = [Float](repeating: 0, count: halfFFT)
            realPart.withUnsafeMutableBufferPointer { rBuf in
                imagPart.withUnsafeMutableBufferPointer { iBuf in
                    var split = DSPSplitComplex(realp: rBuf.baseAddress!,
                                                imagp: iBuf.baseAddress!)
                    vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(halfFFT))
                }
            }
            var scale: Float = 1.0 / Float(fftSize * fftSize)
            vDSP_vsmul(power, 1, &scale, &power, 1, vDSP_Length(halfFFT))
            spectra.append(power)
        }
        return spectra
    }

    private func applyMelFilterBank(_ spectra: [[Float]]) -> [[Float]] {
        let halfFFT = fftSize / 2 + 1
        return spectra.map { spectrum in
            var melEnergies = [Float](repeating: 0, count: numMelBins)
            for m in 0..<numMelBins {
                let filter    = melFilterBank[m]
                let filterLen = min(filter.count, halfFFT, spectrum.count)
                var energy: Float = 0
                vDSP_dotpr(spectrum, 1, filter, 1, &energy, vDSP_Length(filterLen))
                melEnergies[m] = log(max(energy, 1e-10))
            }
            return melEnergies
        }
    }

    /// Fallback 统计池化 (均值 + 标准差 → 160 维, 零填充到 192)
    private func poolAndNormalize(_ melFeatures: [[Float]]) -> [Float] {
        guard !melFeatures.isEmpty else {
            return [Float](repeating: 0, count: Self.embeddingDim)
        }

        let N = numMelBins
        var mean     = [Float](repeating: 0, count: N)
        var variance = [Float](repeating: 0, count: N)

        for frame in melFeatures {
            vDSP_vadd(mean, 1, frame, 1, &mean, 1, vDSP_Length(N))
        }
        var cnt = Float(melFeatures.count)
        vDSP_vsdiv(mean, 1, &cnt, &mean, 1, vDSP_Length(N))

        for frame in melFeatures {
            var diff = [Float](repeating: 0, count: N)
            vDSP_vsub(mean, 1, frame, 1, &diff, 1, vDSP_Length(N))
            vDSP_vsq(diff, 1, &diff, 1, vDSP_Length(N))
            vDSP_vadd(variance, 1, diff, 1, &variance, 1, vDSP_Length(N))
        }
        vDSP_vsdiv(variance, 1, &cnt, &variance, 1, vDSP_Length(N))

        var stddev  = [Float](repeating: 0, count: N)
        var sqrtBuf = [Float](repeating: 0, count: N)
        var eps: Float = 1e-6
        vDSP_vsadd(variance, 1, &eps, &sqrtBuf, 1, vDSP_Length(N))
        var n = Int32(N)
        vvsqrtf(&stddev, sqrtBuf, &n)

        var pooled = mean + stddev  // 160
        if pooled.count < Self.embeddingDim {
            pooled.append(contentsOf: [Float](repeating: 0,
                                              count: Self.embeddingDim - pooled.count))
        }
        return Self.l2Normalize(Array(pooled.prefix(Self.embeddingDim)))
    }

    // MARK: - Mel 滤波器组

    private static func createMelFilterBank(numFilters: Int,
                                             fftSize: Int,
                                             sampleRate: Float) -> [[Float]] {
        let halfFFT  = fftSize / 2 + 1
        let lowMel   = hzToMel(0)
        let highMel  = hzToMel(sampleRate / 2)

        var melPoints = [Float]()
        for i in 0...(numFilters + 1) {
            melPoints.append(lowMel + Float(i) * (highMel - lowMel) / Float(numFilters + 1))
        }
        let hzPoints  = melPoints.map { melToHz($0) }
        let binPoints = hzPoints.map { Int(floor($0 * Float(fftSize) / sampleRate)) }

        var filterBank = [[Float]]()
        for m in 0..<numFilters {
            var filter = [Float](repeating: 0, count: halfFFT)
            let left = binPoints[m], center = binPoints[m + 1], right = binPoints[m + 2]
            for k in left..<center  where k < halfFFT {
                filter[k] = Float(k - left)  / Float(max(1, center - left))
            }
            for k in center..<right where k < halfFFT {
                filter[k] = Float(right - k) / Float(max(1, right - center))
            }
            filterBank.append(filter)
        }
        return filterBank
    }

    private static func hzToMel(_ hz: Float) -> Float { 2595 * log10(1 + hz / 700) }
    private static func melToHz(_ mel: Float) -> Float { 700 * (pow(10, mel / 2595) - 1) }

    static func l2Normalize(_ v: [Float]) -> [Float] {
        var norm: Float = 0
        vDSP_dotpr(v, 1, v, 1, &norm, vDSP_Length(v.count))
        norm = sqrt(norm)
        guard norm > 0 else { return v }
        var result = [Float](repeating: 0, count: v.count)
        var n = norm
        vDSP_vsdiv(v, 1, &n, &result, 1, vDSP_Length(v.count))
        return result
    }
}
