import SwiftUI
import UniformTypeIdentifiers

// MARK: - ExportPanelView
// 纯值类型输入（ExportSnapshot），零 SwiftData / @Observable 依赖

struct ExportPanelView: View {
    let snapshot: ExportSnapshot
    @Binding var isPresented: Bool
    /// 回调：(内容文本, 文件名) — 父视图负责弹 NSSavePanel
    var onExport: (String, String) -> Void

    @State private var format: ExportFormat = .markdown
    @State private var includeNotes = true
    @State private var includeAIPolish = true
    @State private var includeVoice = true
    @State private var includeAIEnhancement = true
    @State private var addFrontmatter = true
    @State private var selectedDepts: Set<String>

    init(snapshot: ExportSnapshot, isPresented: Binding<Bool>,
         onExport: @escaping (String, String) -> Void) {
        self.snapshot = snapshot
        self._isPresented = isPresented
        self.onExport = onExport
        self._selectedDepts = State(initialValue: Set(snapshot.selectedDepartmentIds))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题栏
            HStack {
                Image(systemName: "square.and.arrow.up")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("导出调研报告")
                        .font(.headline)
                    Text(snapshot.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 格式
                    GroupBox("导出格式") {
                        Picker("格式", selection: $format) {
                            ForEach(ExportFormat.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()
                        if format == .word {
                            Label("生成 .doc 文件，可用 Word / Pages 打开", systemImage: "info.circle")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    // 内容范围
                    GroupBox("导出内容") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("顾问笔记",       isOn: $includeNotes)
                            Toggle("AI 润色结果",    isOn: $includeAIPolish)
                            Toggle("语音转写记录",    isOn: $includeVoice)
                            if snapshot.aiEnhancement != nil {
                                Toggle("AI 项目分析", isOn: $includeAIEnhancement)
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
                                Text("导出部门").font(.subheadline).fontWeight(.medium)
                                Spacer()
                                Button("全选") { selectedDepts = Set(snapshot.selectedDepartmentIds) }
                                    .buttonStyle(.plain).font(.caption).foregroundStyle(Color.accentColor)
                                Text("/").foregroundStyle(.tertiary).font(.caption)
                                Button("清空") { selectedDepts.removeAll() }
                                    .buttonStyle(.plain).font(.caption).foregroundStyle(Color.accentColor)
                            }
                            ForEach(snapshot.selectedDepartmentIds, id: \.self) { deptId in
                                let name = snapshot.departmentNames[deptId] ?? deptId
                                let count = snapshot.departmentSections[deptId]?
                                    .flatMap(\.items).filter(\.hasContent).count ?? 0

                                Toggle(isOn: Binding(
                                    get: { selectedDepts.contains(deptId) },
                                    set: { if $0 { selectedDepts.insert(deptId) } else { selectedDepts.remove(deptId) } }
                                )) {
                                    HStack {
                                        Text(name)
                                        Spacer()
                                        Text("\(count) 条回答").font(.caption).foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }

            Divider()

            HStack {
                Spacer()
                Button("取消") { isPresented = false }.keyboardShortcut(.cancelAction)
                Button { prepareAndExport() } label: {
                    Label("导出...", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedDepts.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 420, height: 540)
    }

    // MARK: - Generate content from snapshot (no @Model access)

    private func prepareAndExport() {
        let config = ExportConfig(
            addFrontmatter: addFrontmatter,
            includeNotes: includeNotes,
            includeAIPolish: includeAIPolish,
            includeVoice: includeVoice,
            includeAIEnhancement: includeAIEnhancement,
            useWikiLinks: true,
            departmentFilter: Array(selectedDepts)
        )
        let baseName = "\(snapshot.displayName) 调研报告"

        let content: String
        let fileName: String

        switch format {
        case .markdown:
            content = MarkdownExporter.exportProject(snapshot: snapshot, config: config)
            fileName = "\(baseName).md"
        case .word:
            content = MarkdownExporter.exportProjectAsHTML(snapshot: snapshot, config: config)
            fileName = "\(baseName).doc"
        }

        isPresented = false
        onExport(content, fileName)
    }
}
