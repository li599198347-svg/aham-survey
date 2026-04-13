import Speech

/// Apple Speech 转写引擎 — 使用 SFSpeechRecognizer 进行实时语音识别
@Observable
@MainActor
final class AppleSpeechEngine {
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private(set) var transcript = ""
    private(set) var isTranscribing = false
    private(set) var error: String?

    init(locale: Locale = Locale(identifier: "zh-Hans")) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
    }

    /// 请求语音识别授权
    static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// 开始实时转写 — 配合 AudioCaptureEngine 的 bufferHandler 使用
    func startTranscription() throws -> (AVAudioPCMBuffer, AVAudioTime) -> Void {
        guard let recognizer, recognizer.isAvailable else {
            throw VoiceError.engineNotAvailable
        }

        transcript = ""
        error = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true

        self.recognitionRequest = request
        isTranscribing = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, err in
            guard let self else { return }

            if let result {
                Task { @MainActor in
                    self.transcript = result.bestTranscription.formattedString
                }

                if result.isFinal {
                    Task { @MainActor in
                        self.isTranscribing = false
                    }
                }
            }

            if let err {
                Task { @MainActor in
                    // 忽略取消错误
                    if (err as NSError).code != 216 { // kAFAssistantErrorDomain cancel
                        self.error = err.localizedDescription
                    }
                    self.isTranscribing = false
                }
            }
        }

        // 返回 buffer handler，AudioCaptureEngine 会调用它
        return { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
    }

    /// 停止转写
    func stopTranscription() {
        // End audio first, then finish (not cancel) to get final result
        recognitionRequest?.endAudio()
        recognitionTask?.finish()
        recognitionRequest = nil
        recognitionTask = nil
        isTranscribing = false
    }
}
