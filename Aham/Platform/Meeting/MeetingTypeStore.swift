import Foundation

/// 会议类型持久化（内置 + 用户自定义）
@Observable
final class MeetingTypeStore {
    private(set) var customTypes: [MeetingType] = []

    var allTypes: [MeetingType] { MeetingType.builtIn + customTypes }

    private let storePath: URL

    init() {
        let dir = Self.appSupportDir()
        storePath = dir.appendingPathComponent("meeting_types.json")
        load()
    }

    func add(name: String, sfSymbol: String, analysisHint: String) {
        let t = MeetingType(id: UUID().uuidString, name: name, sfSymbol: sfSymbol,
                            analysisHint: analysisHint, isBuiltIn: false)
        customTypes.append(t)
        save()
    }

    func delete(id: String) {
        customTypes.removeAll { $0.id == id }
        save()
    }

    func type(for id: String) -> MeetingType {
        allTypes.first { $0.id == id } ?? MeetingType.builtIn[0]
    }

    private func load() {
        guard let data = try? Data(contentsOf: storePath),
              let decoded = try? JSONDecoder().decode([MeetingType].self, from: data) else { return }
        customTypes = decoded.filter { !$0.isBuiltIn }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(customTypes) {
            try? data.write(to: storePath, options: .atomic)
        }
    }

    static func appSupportDir() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Aham", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
