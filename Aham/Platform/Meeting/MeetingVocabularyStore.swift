import Foundation

enum VocabularyCategory: String, Codable, CaseIterable, Identifiable {
    case project   = "project"
    case customer  = "customer"
    case person    = "person"
    case technical = "technical"
    case custom    = "custom"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .project:   "项目名称"
        case .customer:  "客户名称"
        case .person:    "人员名称"
        case .technical: "技术术语"
        case .custom:    "自定义"
        }
    }
    var icon: String {
        switch self {
        case .project:   "folder"
        case .customer:  "building.2"
        case .person:    "person"
        case .technical: "cpu"
        case .custom:    "tag"
        }
    }
}

struct VocabularyTerm: Codable, Identifiable, Hashable {
    var id: String
    var term: String
    var category: VocabularyCategory

    init(term: String, category: VocabularyCategory) {
        self.id = UUID().uuidString
        self.term = term
        self.category = category
    }
}

/// 会议自定义词库（项目名、客户名、术语等），用于提升转写准确度
@Observable
final class MeetingVocabularyStore {
    private(set) var terms: [VocabularyTerm] = []

    private let storePath: URL

    init() {
        let dir = MeetingTypeStore.appSupportDir()
        storePath = dir.appendingPathComponent("meeting_vocabulary.json")
        load()
    }

    var contextualStrings: [String] { terms.map(\.term) }

    func add(term: String, category: VocabularyCategory) {
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !terms.contains(where: { $0.term == trimmed }) else { return }
        terms.append(VocabularyTerm(term: trimmed, category: category))
        save()
    }

    func delete(id: String) {
        terms.removeAll { $0.id == id }
        save()
    }

    func deleteAll() {
        terms.removeAll()
        save()
    }

    /// 从已有项目/客户数据中批量导入建议词
    func importSuggestions(_ words: [String], category: VocabularyCategory) {
        var added = false
        for w in words {
            let t = w.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, !terms.contains(where: { $0.term == t }) else { continue }
            terms.append(VocabularyTerm(term: t, category: category))
            added = true
        }
        if added { save() }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storePath),
              let decoded = try? JSONDecoder().decode([VocabularyTerm].self, from: data) else { return }
        terms = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(terms) {
            try? data.write(to: storePath, options: .atomic)
        }
    }
}
