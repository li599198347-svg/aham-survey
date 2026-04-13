import Foundation
import SwiftData

/// 答案状态
enum AnswerStatus: String, Codable {
    case unanswered     // 未回答
    case answered       // 已回答
    case skipped        // 跳过
    case ignored        // 忽略
    case transferred    // 已转移到其他部门
}

/// 调研答案（SwiftData 持久化，关联 Project）
@Model
final class Answer {
    var id: UUID
    var projectId: UUID
    var departmentId: String
    var questionId: String

    // 答案内容
    var selectedOptions: [String]   // 选中的选项（单选/多选）
    var textValue: String           // 文本答案 / 数字答案
    var otherText: String = ""      // "其他" 选项的补充文本
    var noteText: String            // 顾问笔记

    // AI 增强（Phase 3）
    var polishedText: String        // AI 润色后的文本
    var aiExtractions: String       // AI 提取的结构化数据 (JSON)

    // 语音（Phase 4）
    var voiceTranscript: String     // 语音转写文本
    var speakerLabel: String        // 说话人标记

    // 元信息
    var status: AnswerStatus
    var source: String              // manual, voice, ai
    var createdAt: Date
    var updatedAt: Date

    init(projectId: UUID, departmentId: String, questionId: String) {
        self.id = UUID()
        self.projectId = projectId
        self.departmentId = departmentId
        self.questionId = questionId
        self.selectedOptions = []
        self.textValue = ""
        self.otherText = ""
        self.noteText = ""
        self.polishedText = ""
        self.aiExtractions = ""
        self.voiceTranscript = ""
        self.speakerLabel = ""
        self.status = .unanswered
        self.source = "manual"
        self.createdAt = .now
        self.updatedAt = .now
    }

    var hasContent: Bool {
        !selectedOptions.isEmpty || !textValue.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
