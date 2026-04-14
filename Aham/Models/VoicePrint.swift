import Foundation

/// 声纹角色类型
enum VoicePrintRole: String, Codable, CaseIterable, Identifiable {
    case internal_ = "internal"   // 公司内部
    case external  = "external"   // 外部（客户/供应商/访客）

    var id: String { rawValue }

    var label: String {
        switch self {
        case .internal_: "公司"
        case .external:  "外部"
        }
    }

    var icon: String {
        switch self {
        case .internal_: "person.badge.shield.checkmark"
        case .external:  "person.fill"
        }
    }
}

/// 声纹数据模型
struct VoicePrint: Identifiable, Hashable {
    let id: String              // UUID
    var name: String            // 说话人姓名
    var role: VoicePrintRole    // 角色：公司 / 外部
    var company: String         // 所属单位（外部人员填写，内部可留空）
    var embedding: [Float]      // 声纹嵌入向量 (192维)
    var sampleCount: Int        // 录入样本数
    var createdAt: Date
    var updatedAt: Date

    init(name: String, role: VoicePrintRole, company: String = "", embedding: [Float]) {
        self.id = UUID().uuidString
        self.name = name
        self.role = role
        self.company = company
        self.embedding = embedding
        self.sampleCount = 1
        self.createdAt = .now
        self.updatedAt = .now
    }
}

// MARK: - Codable（含旧版角色迁移）

extension VoicePrint: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, role, company, embedding, sampleCount, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decode(String.self,  forKey: .id)
        name       = try c.decode(String.self,  forKey: .name)
        // 旧版角色兼容：consultant/customer/other → internal_/external
        if let r = try? c.decode(VoicePrintRole.self, forKey: .role) {
            role = r
        } else {
            let raw = (try? c.decode(String.self, forKey: .role)) ?? ""
            role = raw == "customer" ? .external : .internal_
        }
        company    = (try? c.decode(String.self, forKey: .company)) ?? ""
        embedding  = try c.decode([Float].self,  forKey: .embedding)
        sampleCount = try c.decode(Int.self,     forKey: .sampleCount)
        createdAt  = try c.decode(Date.self,     forKey: .createdAt)
        updatedAt  = try c.decode(Date.self,     forKey: .updatedAt)
    }
}

/// 声纹匹配结果
struct SpeakerMatch {
    let voicePrint: VoicePrint
    let similarity: Float       // 余弦相似度 0~1
    let isConfident: Bool       // 是否超过阈值
}
