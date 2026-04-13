import Foundation

/// 声纹角色类型
enum VoicePrintRole: String, Codable, CaseIterable, Identifiable {
    case consultant = "consultant"  // 顾问
    case customer = "customer"      // 客户
    case other = "other"            // 其他

    var id: String { rawValue }

    var label: String {
        switch self {
        case .consultant: "顾问"
        case .customer: "客户"
        case .other: "其他"
        }
    }

    var icon: String {
        switch self {
        case .consultant: "person.badge.shield.checkmark"
        case .customer: "person.fill"
        case .other: "person"
        }
    }
}

/// 声纹数据模型
struct VoicePrint: Codable, Identifiable, Hashable {
    let id: String              // UUID
    var name: String            // 说话人姓名
    var role: VoicePrintRole    // 角色
    var embedding: [Float]      // 声纹嵌入向量 (192维)
    var sampleCount: Int        // 录入样本数
    var createdAt: Date
    var updatedAt: Date

    init(name: String, role: VoicePrintRole, embedding: [Float]) {
        self.id = UUID().uuidString
        self.name = name
        self.role = role
        self.embedding = embedding
        self.sampleCount = 1
        self.createdAt = .now
        self.updatedAt = .now
    }
}

/// 声纹匹配结果
struct SpeakerMatch {
    let voicePrint: VoicePrint
    let similarity: Float       // 余弦相似度 0~1
    let isConfident: Bool       // 是否超过阈值
}
