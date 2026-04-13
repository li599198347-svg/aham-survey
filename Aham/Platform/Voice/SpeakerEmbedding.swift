import Foundation
import Accelerate

/// 说话人嵌入向量引擎
/// 当前实现: 基于 Mel-Fbank 特征提取的简化声纹引擎
/// 后续可替换为 CoreML ECAPA-TDNN 模型
@MainActor
final class SpeakerEmbedding {

    /// 嵌入向量维度 (与 ECAPA-TDNN 192维对齐)
    static let embeddingDim = 192

    /// 匹配阈值 (余弦相似度)
    static let matchThreshold: Float = 0.55

    // MARK: - Mel-Fbank 参数

    private let sampleRate: Float = 16000
    private let fftSize = 512
    private let hopLength = 160        // 10ms @ 16kHz
    private let numMelBins = 80
    private let preemphasis: Float = 0.97

    // Mel 滤波器组 (预计算)
    private let melFilterBank: [[Float]]

    init() {
        melFilterBank = Self.createMelFilterBank(
            numFilters: numMelBins,
            fftSize: 512,
            sampleRate: 16000
        )
    }

    // MARK: - 公开 API

    /// 从 16kHz float32 音频提取声纹嵌入向量
    func extractEmbedding(from audioSamples: [Float]) -> [Float] {
        // 1. 预加重
        let emphasized = applyPreemphasis(audioSamples)

        // 2. 分帧 + 加窗 + FFT → 功率谱
        let powerSpectrum = computePowerSpectrum(emphasized)

        // 3. Mel 滤波器组 → Log Mel-Fbank 特征
        let melFeatures = applyMelFilterBank(powerSpectrum)

        // 4. 均值池化 + L2 归一化 → 嵌入向量
        let embedding = poolAndNormalize(melFeatures)

        return embedding
    }

    /// 计算两个嵌入向量的余弦相似度
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
        vDSP_dotpr(a, 1, a, 1, &normA, vDSP_Length(a.count))
        vDSP_dotpr(b, 1, b, 1, &normB, vDSP_Length(b.count))

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }

        return dotProduct / denominator
    }

    /// 合并多个嵌入向量 (取平均, 用于多次录音注册)
    static func averageEmbeddings(_ embeddings: [[Float]]) -> [Float] {
        guard let first = embeddings.first else { return [] }
        guard embeddings.count > 1 else { return first }

        var result = [Float](repeating: 0, count: first.count)
        for embedding in embeddings {
            vDSP_vadd(result, 1, embedding, 1, &result, 1, vDSP_Length(first.count))
        }
        var count = Float(embeddings.count)
        vDSP_vsdiv(result, 1, &count, &result, 1, vDSP_Length(first.count))

        // L2 归一化
        return l2Normalize(result)
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

        // 汉宁窗
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        let halfFFT = fftSize / 2 + 1
        var spectra = [[Float]]()
        spectra.reserveCapacity(numFrames)

        // FFT setup
        guard let fftSetup = vDSP_create_fftsetup(vDSP_Length(log2(Float(fftSize))), FFTRadix(kFFTRadix2)) else {
            return []
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        var realPart = [Float](repeating: 0, count: halfFFT)
        var imagPart = [Float](repeating: 0, count: halfFFT)

        for frame in 0..<numFrames {
            let start = frame * hopLength
            let end = min(start + fftSize, signal.count)
            var frameSamples = [Float](repeating: 0, count: fftSize)
            let copyCount = end - start
            frameSamples[0..<copyCount] = signal[start..<end]

            // 加窗
            vDSP_vmul(frameSamples, 1, window, 1, &frameSamples, 1, vDSP_Length(fftSize))

            // Pack for FFT
            frameSamples.withUnsafeMutableBufferPointer { buf in
                buf.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfFFT) { complexBuf in
                    realPart.withUnsafeMutableBufferPointer { realBuf in
                        imagPart.withUnsafeMutableBufferPointer { imagBuf in
                            var splitComplex = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                            vDSP_ctoz(complexBuf, 2, &splitComplex, 1, vDSP_Length(halfFFT))
                            vDSP_fft_zrip(fftSetup, &splitComplex, 1, vDSP_Length(log2(Float(fftSize))), FFTDirection(FFT_FORWARD))
                        }
                    }
                }
            }

            // Power spectrum = real^2 + imag^2
            var power = [Float](repeating: 0, count: halfFFT)
            realPart.withUnsafeMutableBufferPointer { realBuf in
                imagPart.withUnsafeMutableBufferPointer { imagBuf in
                    var splitForMags = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                    vDSP_zvmags(&splitForMags, 1, &power, 1, vDSP_Length(halfFFT))
                }
            }

            // Scale
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
                let filter = melFilterBank[m]
                let filterLen = min(filter.count, halfFFT, spectrum.count)
                var energy: Float = 0
                vDSP_dotpr(spectrum, 1, filter, 1, &energy, vDSP_Length(filterLen))
                // Log compression
                melEnergies[m] = log(max(energy, 1e-10))
            }
            return melEnergies
        }
    }

    private func poolAndNormalize(_ melFeatures: [[Float]]) -> [Float] {
        guard !melFeatures.isEmpty else {
            return [Float](repeating: 0, count: Self.embeddingDim)
        }

        let numBins = melFeatures[0].count  // 80

        // 统计池化: 均值 + 标准差 → 160维
        var mean = [Float](repeating: 0, count: numBins)
        var variance = [Float](repeating: 0, count: numBins)

        for frame in melFeatures {
            vDSP_vadd(mean, 1, frame, 1, &mean, 1, vDSP_Length(numBins))
        }
        var count = Float(melFeatures.count)
        vDSP_vsdiv(mean, 1, &count, &mean, 1, vDSP_Length(numBins))

        for frame in melFeatures {
            var diff = [Float](repeating: 0, count: numBins)
            vDSP_vsub(mean, 1, frame, 1, &diff, 1, vDSP_Length(numBins))
            vDSP_vsq(diff, 1, &diff, 1, vDSP_Length(numBins))
            vDSP_vadd(variance, 1, diff, 1, &variance, 1, vDSP_Length(numBins))
        }
        vDSP_vsdiv(variance, 1, &count, &variance, 1, vDSP_Length(numBins))

        var stddev = [Float](repeating: 0, count: numBins)
        var sqrtResult = [Float](repeating: 0, count: numBins)
        // sqrt(variance + eps)
        var eps: Float = 1e-6
        vDSP_vsadd(variance, 1, &eps, &sqrtResult, 1, vDSP_Length(numBins))
        var n = Int32(numBins)
        vvsqrtf(&stddev, sqrtResult, &n)

        // 拼接: [mean(80) | stddev(80)] = 160维
        var pooled = mean + stddev  // 160维

        // 零填充到 192 维 (匹配 ECAPA-TDNN 维度，后续可替换为投影矩阵)
        if pooled.count < Self.embeddingDim {
            pooled.append(contentsOf: [Float](repeating: 0, count: Self.embeddingDim - pooled.count))
        }
        pooled = Array(pooled.prefix(Self.embeddingDim))

        return Self.l2Normalize(pooled)
    }

    // MARK: - Mel 滤波器组

    private static func createMelFilterBank(numFilters: Int, fftSize: Int, sampleRate: Float) -> [[Float]] {
        let halfFFT = fftSize / 2 + 1
        let lowMel = hzToMel(0)
        let highMel = hzToMel(sampleRate / 2)

        // 均匀分布的 Mel 点
        var melPoints = [Float]()
        for i in 0...(numFilters + 1) {
            let mel = lowMel + Float(i) * (highMel - lowMel) / Float(numFilters + 1)
            melPoints.append(mel)
        }

        // 转换回 Hz 并映射到 FFT bin
        let hzPoints = melPoints.map { melToHz($0) }
        let binPoints = hzPoints.map { Int(floor($0 * Float(fftSize) / sampleRate)) }

        var filterBank = [[Float]]()
        for m in 0..<numFilters {
            var filter = [Float](repeating: 0, count: halfFFT)
            let left = binPoints[m]
            let center = binPoints[m + 1]
            let right = binPoints[m + 2]

            for k in left..<center where k < halfFFT {
                filter[k] = Float(k - left) / Float(max(1, center - left))
            }
            for k in center..<right where k < halfFFT {
                filter[k] = Float(right - k) / Float(max(1, right - center))
            }
            filterBank.append(filter)
        }

        return filterBank
    }

    private static func hzToMel(_ hz: Float) -> Float {
        2595.0 * log10(1.0 + hz / 700.0)
    }

    private static func melToHz(_ mel: Float) -> Float {
        700.0 * (pow(10.0, mel / 2595.0) - 1.0)
    }

    private static func l2Normalize(_ vector: [Float]) -> [Float] {
        var norm: Float = 0
        vDSP_dotpr(vector, 1, vector, 1, &norm, vDSP_Length(vector.count))
        norm = sqrt(norm)
        guard norm > 0 else { return vector }
        var result = [Float](repeating: 0, count: vector.count)
        var normValue = norm
        vDSP_vsdiv(vector, 1, &normValue, &result, 1, vDSP_Length(vector.count))
        return result
    }
}
