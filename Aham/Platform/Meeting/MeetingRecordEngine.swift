import AVFoundation
import Speech
import SwiftData
import Foundation

/// 全局会议录音引擎 — 与 View 生命周期解耦，可后台持续运行
@Observable
@MainActor
final class MeetingRecordEngine {

    // MARK: - Public State

    var isRecording = false
    var recordingDuration: TimeInterval = 0
    var currentLevel: Float = 0          // 0~1 音量
    var currentSpeaker = ""              // 当前识别到的说话人
    var liveSegments: [LiveSegment] = [] // 实时转写段落
    var activeMeetingId: UUID?
    var lastError: String?

    /// 实时转写段落（临时，用于 UI）
    struct LiveSegment: Identifiable {
        let id = UUID()
        var startTime: TimeInterval
        var speakerName: String
        var text: String
        var isFinal: Bool
    }

    // MARK: - Dependencies

    var voicePrintStore: VoicePrintStore?
    var vocabularyStore: MeetingVocabularyStore?

    // MARK: - Private

    private let capture = AudioCaptureEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var windowStartTime: TimeInterval = 0

    private var durationTimer: Timer?
    private var speakerTimer: Timer?
    private var sessionStart: Date?

    private var recentSamples: [Float] = []
    private let speakerCheckInterval: TimeInterval = 8.0

    // MARK: - Meetings Directory

    static var meetingsBaseDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("Aham/Meetings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func meetingDir(id: UUID) -> URL {
        let dir = Self.meetingsBaseDir.appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Start

    func start(meetingId: UUID) async throws {
        guard !isRecording else { return }

        // 权限
        let speechStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard speechStatus == .authorized else {
            lastError = "需要语音识别权限，请在系统偏好设置中授权"
            throw RecordError.noPermission
        }

        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-Hans-CN"))

        // 设置 bufferHandler → 转写 + 样本收集
        capture.bufferHandler = { [weak self] buffer, _ in
            guard let self else { return }
            self.recognitionRequest?.append(buffer)
            // 收集样本用于说话人识别
            if let channel = buffer.floatChannelData {
                let n = Int(buffer.frameLength)
                let samples = Array(UnsafeBufferPointer(start: channel[0], count: n))
                Task { @MainActor [weak self] in
                    self?.recentSamples.append(contentsOf: samples)
                    let maxSamples = Int(self?.capture.captureSampleRate ?? 48000) * 5
                    if (self?.recentSamples.count ?? 0) > maxSamples {
                        self?.recentSamples = Array(self?.recentSamples.suffix(maxSamples) ?? [])
                    }
                    let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(max(samples.count, 1)))
                    self?.currentLevel = min(rms * 12, 1.0)
                }
            }
        }

        try capture.startCapture()
        startRecognitionWindow()

        activeMeetingId = meetingId
        sessionStart    = Date()
        isRecording     = true

        liveSegments    = []
        currentSpeaker  = ""
        lastError       = nil

        // 计时器
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let start = self.sessionStart else { return }
                self.recordingDuration = Date().timeIntervalSince(start)
            }
        }

        // 说话人识别定时器
        speakerTimer = Timer.scheduledTimer(withTimeInterval: speakerCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.identifySpeaker() }
        }
    }

    // MARK: - Stop

    /// 停止录音，返回 (音频文件路径, 转写段落列表)
    func stop(meetingId: UUID) -> (audioRelPath: String, segments: [LiveSegment]) {
        guard isRecording else { return ("", []) }

        durationTimer?.invalidate();  durationTimer = nil
        speakerTimer?.invalidate();   speakerTimer = nil

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask    = nil

        let captureResult = capture.stopCapture()

        isRecording      = false
        activeMeetingId  = nil

        // 移动录音文件到会议目录
        var relPath = ""
        if let (tmpURL, _) = captureResult {
            let destDir = meetingDir(id: meetingId)
            let destURL = destDir.appendingPathComponent("recording.caf")
            try? FileManager.default.removeItem(at: destURL)
            if (try? FileManager.default.moveItem(at: tmpURL, to: destURL)) != nil {
                relPath = "\(meetingId.uuidString)/recording.caf"
            }
        }

        let finals = liveSegments.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        return (relPath, finals)
    }

    // MARK: - Recognition Window (rolling)

    private func startRecognitionWindow() {
        recognitionTask?.cancel()
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true
        recognitionRequest?.addsPunctuation = true
        if let vocab = vocabularyStore?.contextualStrings, !vocab.isEmpty {
            recognitionRequest?.contextualStrings = Array(vocab.prefix(200))
        }

        windowStartTime = recordingDuration

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest!) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    self.handleResult(result)
                }
                // 识别结束（超时或完成）→ 开新窗口
                if result?.isFinal == true || (error != nil && self.isRecording) {
                    self.startRecognitionWindow()
                }
            }
        }
    }

    private func handleResult(_ result: SFSpeechRecognitionResult) {
        let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        let speaker = currentSpeaker.isEmpty ? "未知" : currentSpeaker

        if result.isFinal {
            // 结束当前 pending 段或新增
            if let idx = liveSegments.lastIndex(where: { !$0.isFinal }) {
                liveSegments[idx].text     = text
                liveSegments[idx].isFinal  = true
            } else {
                liveSegments.append(LiveSegment(startTime: windowStartTime,
                                                speakerName: speaker, text: text, isFinal: true))
            }
        } else {
            if let idx = liveSegments.lastIndex(where: { !$0.isFinal }) {
                liveSegments[idx].text        = text
                liveSegments[idx].speakerName = speaker
            } else {
                liveSegments.append(LiveSegment(startTime: windowStartTime,
                                                speakerName: speaker, text: text, isFinal: false))
            }
        }
    }

    // MARK: - Speaker Identification

    private func identifySpeaker() {
        guard let store = voicePrintStore, !recentSamples.isEmpty, !store.voicePrints.isEmpty else { return }
        let samples    = recentSamples
        let sampleRate = capture.captureSampleRate
        if let match = store.identify(audioSamples: samples,
                                      captureSampleRate: sampleRate), match.isConfident {
            currentSpeaker = match.voicePrint.name
            // 更新最近 pending 段落的 speakerName
            if let idx = liveSegments.lastIndex(where: { !$0.isFinal }) {
                liveSegments[idx].speakerName = currentSpeaker
            }
        }
    }

    // MARK: - Error

    enum RecordError: Error, LocalizedError {
        case noPermission
        var errorDescription: String? {
            switch self { case .noPermission: "缺少麦克风或语音识别权限" }
        }
    }
}
