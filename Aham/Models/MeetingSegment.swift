import Foundation
import SwiftData

@Model
final class MeetingSegment {
    @Attribute(.unique) var id: UUID
    var startTime: TimeInterval   // seconds from recording start
    var speakerName: String       // voice print name or "未知A"
    var text: String
    var confidence: Float         // recognition confidence

    init(startTime: TimeInterval, speakerName: String, text: String, confidence: Float = 1.0) {
        self.id = UUID()
        self.startTime = startTime
        self.speakerName = speakerName
        self.text = text
        self.confidence = confidence
    }

    var timeLabel: String {
        let m = Int(startTime) / 60
        let s = Int(startTime) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
