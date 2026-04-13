import Foundation

/// 语音服务协议 — 平台级，所有模块共享
/// Phase 4 实现：AudioCaptureEngine + SpeechEngine + DiarizationEngine
protocol VoiceProvider {
    /// 开始录音
    func startRecording() async throws
    /// 停止录音并返回转写结果
    func stopRecording() async throws -> VoiceResult
    /// 是否正在录音
    var isRecording: Bool { get }
}

/// 语音转写结果
struct VoiceResult: Sendable {
    let transcript: String
    let segments: [VoiceSegment]
    let duration: TimeInterval
}

/// 语音片段（含说话人标记）
struct VoiceSegment: Sendable, Identifiable {
    let id = UUID()
    let text: String
    let speaker: String        // 说话人标签
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Double
}

/// 语音服务配置
struct VoiceConfig: Codable, Equatable {
    var enabled: Bool
    var engine: VoiceEngine
    var autoTranscribe: Bool   // 录音结束后自动转写
    var showSpeakers: Bool     // 显示说话人标记

    static let `default` = VoiceConfig(
        enabled: false,
        engine: .system,
        autoTranscribe: true,
        showSpeakers: true
    )
}

/// 语音引擎（当前仅 macOS 系统语音 + 声纹识别）
enum VoiceEngine: String, Codable, CaseIterable {
    case system = "system"

    var label: String { "macOS 系统语音识别 + 声纹识别" }
}

enum VoiceError: LocalizedError {
    case noPermission
    case engineNotAvailable

    var errorDescription: String? {
        switch self {
        case .noPermission: "未获得麦克风权限"
        case .engineNotAvailable: "语音引擎不可用"
        }
    }
}
