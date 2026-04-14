import SwiftUI
import UniformTypeIdentifiers

/// 导出配置面板 — 格式、内容范围、部门范围
struct ExportPanelView: View {
    let project: Project
    let answers: [Answer]
    let pluginLoader: PluginLoader

    @Binding var isPresented: Bool

    // 格式
    @State private var format: ExportFormat = .markdown
    // 内容范围
    @State private var includeNotes = true
    @State private var includeAIPolish = true
    @State private var includeVoice = true
    @State private var includeAIEnhancement = true
    @State private var addFrontmatter = true
    // 部门范围
    @State private var selectedDepts: Set<String>
    // 状态
    @State private var isExporting = false
    @State private var exportError: String?

    init(project: Project, answers: [Answer], pluginLoader: PluginLoader, isPresented: Binding<Bool>) {
        self.project = project
        self.answers = answers
        self.pluginLoader = pluginLoader
        self._isPresented = isPresented
        self._selectedDepts = State(initialValue: Set(project.selectedDepartmentIds))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题
            HStack {
                Image(systemName: "square.and.arrow.up")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("导出调研报告")
                        .font(.headline)
                    Text(project.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 格式选择
                    GroupBox("导出格式") {
                        Picker("格式", selection: $format) {
                            ForEach(ExportFormat.allCases, id: \.self) { f in
                                Text(f.rawValue).tag(f)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()

                        if format == .word {
                            Label("生成 .doc 文件，可用 Word / Pages 打开", systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // 内容范围
                    GroupBox("导出内容") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("顾问笔记", isOn: $includeNotes)
                            Toggle("AI 润色结果", isOn: $includeAIPolish)
                            Toggle("语音转写记录", isOn: $includeVoice)
                            if project.aiEnhancement != nil {
                                Toggle("AI 项目分析（行业洞察、补充问题）", isOn: $includeAIEnhancement)
                            }
                            Divider()
                            Toggle("包含 YAML 文件头（Obsidian 兼容）", isOn: $addFrontmatter)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // 部门范围
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("导出部门")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Button("全选") { selectedDepts = Set(project.selectedDepartmentIds) }
                                    .buttonStyle(.plain)
                                    .font(.caption)
                                    .foregroundStyle(Color.accentColor)
                                Text("/")
                                    .foregroundStyle(.tertiary)
                                    .font(.caption)
                                Button("清空") { selectedDepts.removeAll() }
                                    .buttonStyle(.plain)
                                    .font(.caption)
                                    .foregroundStyle(Color.accentColor)
                            }

                            ForEach(project.selectedDepartmentIds, id: \.self) { deptId in
                                let dept = pluginLoader.departments.first { $0.id == deptId }
                                let name = dept?.name ?? deptId
                                let count = answers.filter { $0.departmentId == deptId && $0.hasContent }.count

                                Toggle(isOn: Binding(
                                    get: { selectedDepts.contains(deptId) },
                                    set: { if $0 { selectedDepts.insert(deptId) } else { selectedDepts.remove(deptId) } }
                                )) {
                                    HStack {
                                        if let icon = dept?.icon {
                                            Image(systemName: icon)
                                                .foregroundStyle(.secondary)
                                                .frame(width: 16)
                                        }
                                        Text(name)
                                        Spacer()
                                        Text("\(count) 条回答")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }

            Divider()

            // 底部操作
            HStack {
                if let error = exportError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                Spacer()
                Button("取消") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    doExport()
                } label: {
                    if isExporting {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("导出中...")
                        }
                    } else {
                        Label("导出...", systemImage: "square.and.arrow.up")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedDepts.isEmpty || isExporting)
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 420, height: 580)
    }

    // MARK: - Export

    private func doExport() {
        let config = ExportConfig(
            addFrontmatter: addFrontmatter,
            includeNotes: includeNotes,
            includeAIPolish: includeAIPolish,
            includeVoice: includeVoice,
            includeAIEnhancement: includeAIEnhancement,
            useWikiLinks: true,
            departmentFilter: Array(selectedDepts)
        )

        let panel = NSSavePanel()
        let fileName = "\(project.displayName) 调研报告"

        switch format {
        case .markdown:
            panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
            panel.nameFieldStringValue = "\(fileName).md"
        case .word:
            panel.allowedContentTypes = [UTType(filenameExtension: "doc") ?? .html]
            panel.nameFieldStringValue = "\(fileName).doc"
        }
        panel.message = "选择保存位置"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        exportError = nil
        do {
            let content: String
            switch format {
            case .markdown:
                content = MarkdownExporter.exportProject(
                    project: project, answers: answers,
                    pluginLoader: pluginLoader, config: config
                )
            case .word:
                content = MarkdownExporter.exportProjectAsHTML(
                    project: project, answers: answers,
                    pluginLoader: pluginLoader, config: config
                )
            }
            try content.write(to: url, atomically: true, encoding: .utf8)
            isPresented = false
        } catch {
            exportError = error.localizedDescription
        }
    }
}
