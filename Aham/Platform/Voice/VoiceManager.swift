import AVFoundation
import Speech

/// 语音管理器 — 统一管理录音采集和语音转写
@Observable
@MainActor
final class VoiceManager {
    let capture = AudioCaptureEngine()
    let speech = AppleSpeechEngine()

    private(set) var state: VoiceState = .idle
    private(set) var recordingDuration: TimeInterval = 0
    private(set) var lastResult: VoiceResult?
    private(set) var permissionGranted = false

    /// 当前识别到的说话人
    private(set) var currentSpeaker: SpeakerMatch?

    /// 声纹识别引擎
    private let speakerEmbedding = SpeakerEmbedding()

    /// 音频缓冲用于说话人识别
    private var audioBuffer: [Float] = []
    private let speakerCheckInterval: TimeInterval = 3.0  // 每3秒检查一次
    private var lastSpeakerCheckTime: TimeInterval = 0

    private var timer: Timer?

    enum VoiceState: Equatable {
        case idle
        case recording
        case transcribing
        case error(String)
    }

    // MARK: - 权限检查

    func checkPermissions() async {
        // 麦克风权限
        let audioGranted: Bool
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            audioGranted = true
        } else {
            audioGranted = await AVCaptureDevice.requestAccess(for: .audio)
        }

        // 语音识别权限
        let speechStatus = await AppleSpeechEngine.requestAuthorization()
        let speechGranted = speechStatus == .authorized

        permissionGranted = audioGranted && speechGranted
    }

    // MARK: - 录音控制

    /// 声纹库引用 (由外部设置)
    var voicePrintStore: VoicePrintStore?

    /// 开始录音 + 实时转写
    func startRecording(autoTranscribe: Bool = true) async throws {
        if !permissionGranted {
            await checkPermissions()
        }
        guard permissionGranted else {
            state = .error("未获得麦克风或语音识别权限")
            throw VoiceError.noPermission
        }

        // 重置说话人识别状态
        audioBuffer = []
        lastSpeakerCheckTime = 0
        currentSpeaker = nil

        // 启动语音识别（如果启用自动转写）
        if autoTranscribe {
            let handler = try speech.startTranscription()
            capture.bufferHandler = { [weak self] buffer, time in
                handler(buffer, time)
                // 同时收集音频用于说话人识别
                self?.collectAudioForSpeakerID(buffer: buffer)
            }
        } else {
            capture.bufferHandler = { [weak self] buffer, _ in
                self?.collectAudioForSpeakerID(buffer: buffer)
            }
        }

        // 启动音频采集
        try capture.startCapture()

        state = .recording
        recordingDuration = 0

        // 录音计时器
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.recordingDuration += 0.1
                // 定期检查说话人
                if self.recordingDuration - self.lastSpeakerCheckTime >= self.speakerCheckInterval {
                    self.checkSpeaker()
                }
            }
        }
    }

    /// 停止录音，返回转写结果
    func stopRecording() -> VoiceResult {
        timer?.invalidate()
        timer = nil

        // 停止转写
        speech.stopTranscription()
        capture.bufferHandler = nil

        // 停止采集
        let captureResult = capture.stopCapture()
        let duration = captureResult?.duration ?? recordingDuration

        let transcript = speech.transcript
        let result = VoiceResult(
            transcript: transcript,
            segments: [],  // Apple Speech 不支持说话人标记，segments 为空
            duration: duration
        )

        lastResult = result
        state = .idle
        recordingDuration = 0

        return result
    }

    /// 取消录音（不保存结果）
    func cancelRecording() {
        timer?.invalidate()
        timer = nil
        speech.stopTranscription()
        capture.bufferHandler = nil
        _ = capture.stopCapture()
        state = .idle
        recordingDuration = 0
    }

    /// 格式化录音时长
    var formattedDuration: String {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - 说话人识别

    /// 收集音频缓冲用于说话人识别 (从音频回调线程调用)
    private nonisolated func collectAudioForSpeakerID(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))

        let sampleRate = Int(buffer.format.sampleRate)
        Task { @MainActor [weak self] in
            self?.audioBuffer.append(contentsOf: samples)
            // 保留最近 5 秒的音频（基于实际采样率）
            let maxSamples = sampleRate * 5
            if let count = self?.audioBuffer.count, count > maxSamples {
                self?.audioBuffer.removeFirst(count - maxSamples)
            }
        }
    }

    /// 检查当前说话人身份
    private func checkSpeaker() {
        guard let store = voicePrintStore, !store.voicePrints.isEmpty else { return }

        let sampleRate = Int(capture.inputFormat.sampleRate)
        guard audioBuffer.count > sampleRate else { return } // 至少 1 秒音频

        lastSpeakerCheckTime = recordingDuration

        // 取最近 3 秒的音频进行匹配
        let checkSamples = Array(audioBuffer.suffix(sampleRate * 3))
        let match = store.identify(audioSamples: checkSamples)

        if let match, match.isConfident {
            currentSpeaker = match
        }
    }
}
