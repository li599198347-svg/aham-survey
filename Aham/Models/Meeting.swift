import Foundation
import SwiftData

// MARK: - Status

enum MeetingStatus: String, Codable, CaseIterable {
    case recording    = "recording"
    case paused       = "paused"       // 暂停中，可续录
    case transcribing = "transcribing"
    case analyzing    = "analyzing"
    case completed    = "completed"

    var label: String {
        switch self {
        case .recording:    "录音中"
        case .paused:       "暂停中"
        case .transcribing: "转写中"
        case .analyzing:    "分析中"
        case .completed:    "已完成"
        }
    }
    var icon: String {
        switch self {
        case .recording:    "record.circle"
        case .paused:       "pause.circle.fill"
        case .transcribing: "waveform"
        case .analyzing:    "brain"
        case .completed:    "checkmark.circle.fill"
        }
    }
}

// MARK: - Meeting

@Model
final class Meeting {
    @Attribute(.unique) var id: UUID
    var title: String
    var typeId: String             // MeetingType.id
    var date: Date
    var duration: TimeInterval     // seconds
    var statusRaw: String          // MeetingStatus.rawValue
    var audioPath: String          // relative: {id}/recording.m4a
    var participants: [String]
    var summary: String
    var minutesMarkdown: String
    var resolutions: [String]
    var linkedProjectId: UUID?     // optional link to survey Project
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade) var segments: [MeetingSegment] = []
    @Relationship(deleteRule: .cascade) var todos: [MeetingTodo] = []

    var status: MeetingStatus {
        get { MeetingStatus(rawValue: statusRaw) ?? .completed }
        set { statusRaw = newValue.rawValue; updatedAt = .now }
    }

    init(title: String, typeId: String, linkedProjectId: UUID? = nil) {
        self.id = UUID()
        self.title = title
        self.typeId = typeId
        self.date = .now
        self.duration = 0
        self.statusRaw = MeetingStatus.recording.rawValue
        self.audioPath = ""
        self.participants = []
        self.summary = ""
        self.minutesMarkdown = ""
        self.resolutions = []
        self.linkedProjectId = linkedProjectId
        self.createdAt = .now
        self.updatedAt = .now
    }

    // MARK: - Helpers

    var durationLabel: String {
        let total = Int(duration)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    var participantsLabel: String {
        participants.joined(separator: "、")
    }

    /// 绝对音频文件 URL
    func audioURL(baseDir: URL) -> URL? {
        guard !audioPath.isEmpty else { return nil }
        return baseDir.appendingPathComponent(audioPath)
    }
}
