import AVFoundation

/// 音频采集引擎 — 使用 AVAudioEngine 录制麦克风音频
@Observable
@MainActor
final class AudioCaptureEngine {
    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var fileURL: URL?

    private(set) var isCapturing = false
    private(set) var currentLevel: Float = 0 // 0.0 ~ 1.0 音量电平

    /// 最近一次录音的原始 PCM 样本 (用于声纹注册/测试)
    private(set) var lastRecordingBuffer: [Float] = []
    private var recordingBuffer: [Float] = []

    /// 实时音频缓冲回调 (用于 Speech 引擎)
    var bufferHandler: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?

    /// 开始采集麦克风音频
    func startCapture() throws {
        guard !isCapturing else { return }

        recordingBuffer = []
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        // 创建临时录音文件
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("aham_recording_\(UUID().uuidString).caf")
        audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        fileURL = url

        let file = audioFile
        let handler = bufferHandler
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, time in
            // 写入文件
            try? file?.write(from: buffer)

            // 收集原始 PCM 样本
            if let channelData = buffer.floatChannelData {
                let frameLength = Int(buffer.frameLength)
                let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
                Task { @MainActor [weak self] in
                    self?.recordingBuffer.append(contentsOf: samples)
                }
            }

            // 计算音量电平
            self?.calculateAndUpdateLevel(buffer: buffer)

            // 回调给 Speech 引擎
            handler?(buffer, time)
        }

        engine.prepare()
        try engine.start()
        isCapturing = true
    }

    /// 停止采集，返回录音文件 URL 和时长
    func stopCapture() -> (url: URL, duration: TimeInterval)? {
        guard isCapturing else { return nil }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCapturing = false
        currentLevel = 0
        lastRecordingBuffer = recordingBuffer
        recordingBuffer = []

        guard let url = fileURL, let file = audioFile else { return nil }

        let duration = Double(file.length) / file.processingFormat.sampleRate
        audioFile = nil
        fileURL = nil

        return (url, duration)
    }

    /// 获取输入节点的音频格式
    var inputFormat: AVAudioFormat {
        engine.inputNode.outputFormat(forBus: 0)
    }

    /// 麦克风硬件的原生采样率 (通常 48000 Hz on Mac)
    var captureSampleRate: Double {
        engine.inputNode.outputFormat(forBus: 0).sampleRate
    }

    // MARK: - Private

    private nonisolated func calculateAndUpdateLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0, channelCount > 0 else { return }

        var sum: Float = 0
        for frame in 0..<frameLength {
            let sample = channelData[0][frame]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))
        let db = 20 * log10(max(rms, 1e-6))
        let normalized = max(0, min(1, (db + 60) / 60))

        Task { @MainActor [weak self] in
            self?.currentLevel = normalized
        }
    }
}
