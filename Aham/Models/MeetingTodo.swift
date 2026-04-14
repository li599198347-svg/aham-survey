import Foundation
import SwiftData

@Model
final class MeetingTodo {
    @Attribute(.unique) var id: UUID
    var content: String
    var assignee: String
    var dueText: String        // e.g. "下周五"、"本周三前"
    var isDone: Bool
    var sourceText: String     // 原始转写文本溯源

    init(content: String, assignee: String = "", dueText: String = "", sourceText: String = "") {
        self.id = UUID()
        self.content = content
        self.assignee = assignee
        self.dueText = dueText
        self.isDone = false
        self.sourceText = sourceText
    }
}
