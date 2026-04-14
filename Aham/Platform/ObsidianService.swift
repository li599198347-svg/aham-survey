import Foundation
import AppKit
import UniformTypeIdentifiers

/// Obsidian 集成服务 — 平台级
/// Vault 路径管理 + Markdown 写入 + Obsidian URI 集成
protocol ObsidianProvider {
    /// 导出内容到 Obsidian Vault
    func exportToVault(content: ObsidianContent) async throws
    /// 检查 Vault 是否可用
    func isAvailable() -> Bool
    /// 在 Obsidian 中打开指定笔记
    func openNote(path: String) async throws
}

/// 导出内容
struct ObsidianContent: Sendable {
    let title: String
    let markdown: String
    let tags: [String]
    let folder: String
}

/// Obsidian 配置
struct ObsidianConfig: Codable, Equatable {
    var enabled: Bool
    var vaultPath: String
    var exportFolder: String
    var autoExport: Bool
    var wikiLinks: Bool
    var addFrontmatter: Bool
    var vaultBookmark: Data?  // Security-Scoped Bookmark

    static let `default` = ObsidianConfig(
        enabled: false,
        vaultPath: "",
        exportFolder: "Aham",
        autoExport: false,
        wikiLinks: true,
        addFrontmatter: true,
        vaultBookmark: nil
    )

    /// 从 bookmark 恢复 URL 并获取访问权限
    func resolveVaultURL() -> URL? {
        guard let bookmark = vaultBookmark else {
            // 无 bookmark，回退到路径直接访问
            guard !vaultPath.isEmpty else { return nil }
            return URL(fileURLWithPath: vaultPath)
        }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            return nil
        }
        return url
    }

    /// 从用户选择的 URL 创建 bookmark
    static func createBookmark(from url: URL) -> Data? {
        try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }
}

enum ObsidianError: LocalizedError {
    case vaultNotFound
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .vaultNotFound: "未找到 Obsidian Vault 目录"
        case .exportFailed(let msg): "导出失败: \(msg)"
        }
    }
}

/// Obsidian Vault 文件系统集成
final class ObsidianVaultProvider: ObsidianProvider {
    private let config: ObsidianConfig

    init(config: ObsidianConfig) {
        self.config = config
    }

    func isAvailable() -> Bool {
        guard config.enabled, !config.vaultPath.isEmpty else { return false }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: config.vaultPath, isDirectory: &isDir) && isDir.boolValue
    }

    func exportToVault(content: ObsidianContent) async throws {
        guard config.enabled else { throw ObsidianError.vaultNotFound }

        // 通过 Security-Scoped Bookmark 获取访问权限
        guard let vaultURL = config.resolveVaultURL() else {
            throw ObsidianError.vaultNotFound
        }

        let accessing = vaultURL.startAccessingSecurityScopedResource()
        defer {
            if accessing { vaultURL.stopAccessingSecurityScopedResource() }
        }

        let folderURL = vaultURL
            .appendingPathComponent(config.exportFolder, isDirectory: true)
            .appendingPathComponent(content.folder, isDirectory: true)

        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let safeTitle = content.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let fileURL = folderURL.appendingPathComponent("\(safeTitle).md")

        try content.markdown.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func openNote(path: String) async throws {
        guard config.enabled, !config.vaultPath.isEmpty else { throw ObsidianError.vaultNotFound }

        let vaultName = URL(fileURLWithPath: config.vaultPath).lastPathComponent
        let encodedVault = vaultName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? vaultName
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        let urlString = "obsidian://open?vault=\(encodedVault)&file=\(encodedPath)"

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

/// 导出管理器 — 整合 MarkdownExporter + ObsidianProvider
@Observable
@MainActor
final class ExportManager {
    private(set) var isExporting = false
    private(set) var lastExportPath: String?
    var lastError: String?

    /// 导出项目到 Obsidian Vault
    func exportToObsidian(
        project: Project,
        answers: [Answer],
        pluginLoader: PluginLoader,
        obsidianConfig: ObsidianConfig
    ) async {
        isExporting = true
        lastError = nil
        defer { isExporting = false }

        let exportConfig = ExportConfig(
            addFrontmatter: obsidianConfig.addFrontmatter,
            includeNotes: true,
            includeAIPolish: true,
            includeVoice: true,
            includeAIEnhancement: true,
            useWikiLinks: obsidianConfig.wikiLinks,
            departmentFilter: nil
        )

        let markdown = MarkdownExporter.exportProject(
            project: project,
            answers: answers,
            pluginLoader: pluginLoader,
            config: exportConfig
        )

        let content = ObsidianContent(
            title: "\(project.displayName) 调研报告",
            markdown: markdown,
            tags: ["调研报告", project.customerName],
            folder: project.displayName
        )

        let provider = ObsidianVaultProvider(config: obsidianConfig)

        do {
            try await provider.exportToVault(content: content)
            lastExportPath = "\(obsidianConfig.exportFolder)/\(project.displayName)"

            // 同时导出各部门独立文件
            for deptId in project.selectedDepartmentIds {
                let deptAnswers = answers.filter { $0.departmentId == deptId }
                guard deptAnswers.contains(where: { $0.hasContent }) else { continue }

                let deptMd = MarkdownExporter.exportDepartment(
                    project: project,
                    departmentId: deptId,
                    answers: deptAnswers,
                    pluginLoader: pluginLoader,
                    config: exportConfig
                )

                let deptName = pluginLoader.departments.first { $0.id == deptId }?.name ?? deptId
                let deptContent = ObsidianContent(
                    title: deptName,
                    markdown: deptMd,
                    tags: ["调研", deptName],
                    folder: project.displayName
                )

                try await provider.exportToVault(content: deptContent)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 导出到文件（SavePanel）
    func exportToFile(
        project: Project,
        answers: [Answer],
        pluginLoader: PluginLoader
    ) {
        let markdown = MarkdownExporter.exportProject(
            project: project,
            answers: answers,
            pluginLoader: pluginLoader
        )

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "\(project.displayName) 调研报告.md"
        panel.message = "选择导出位置"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            lastExportPath = url.path
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 在 Obsidian 中打开导出的笔记
    func openInObsidian(obsidianConfig: ObsidianConfig) {
        guard let path = lastExportPath else { return }
        let provider = ObsidianVaultProvider(config: obsidianConfig)
        Task {
            try? await provider.openNote(path: path)
        }
    }
}
