import SwiftUI

// MARK: - ExportPanelData（轻量，仅用于面板展示，无需预建完整快照）

struct ExportPanelData {
    var projectName: String
    var selectedDeptIds: [String]
    var deptNames: [String: String]          // deptId → 显示名
    var deptAnsweredCounts: [String: Int]    // deptId → 已回答数
    var hasAIEnhancement: Bool
}

// MARK: - ExportPanelView

struct ExportPanelView: View {
    let panelData: ExportPanelData
    @Binding var isPresented: Bool
    /// 用户确认后，异步生成内容 → 返回 (data, fileName)，失败返回 nil
    var onGenerate: (ExportConfig) async -> (Data, String)?
    /// 生成完成后触发 NSSavePanel（由父视图处理）
    var onExport: (Data, String) -> Void

    @State private var format: ExportFormat = .markdown
    @State private var includeNotes = true
    @State private var includeAIPolish = true
    @State private var includeVoice = true
    @State private var includeAIEnhancement = true
    @State private var addFrontmatter = true
    @State private var selectedDepts: Set<String>
    @State private var isGenerating = false
    @State private var generateError: String?

    init(panelData: ExportPanelData,
         isPresented: Binding<Bool>,
         onGenerate: @escaping (ExportConfig) async -> (Data, String)?,
         onExport: @escaping (Data, String) -> Void) {
        self.panelData = panelData
        self._isPresented = isPresented
        self.onGenerate = onGenerate
        self.onExport = onExport
        self._selectedDepts = State(initialValue: Set(panelData.selectedDeptIds))
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
                    Text(panelData.projectName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .disabled(isGenerating)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 导出格式
                    GroupBox("导出格式") {
                        Picker("格式", selection: $format) {
                            ForEach(ExportFormat.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()
                    }

                    // 导出内容
                    GroupBox("导出内容") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("顾问笔记",    isOn: $includeNotes)
                            Toggle("AI 润色结果", isOn: $includeAIPolish)
                            Toggle("语音转写记录", isOn: $includeVoice)
                            if panelData.hasAIEnhancement {
                                Toggle("AI 项目分析", isOn: $includeAIEnhancement)
                            }
                            Divider()
                            Toggle("包含 YAML 文件头（Obsidian 兼容）", isOn: $addFrontmatter)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // 导出部门
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("导出部门").font(.subheadline).fontWeight(.medium)
                                Spacer()
                                Button("全选") { selectedDepts = Set(panelData.selectedDeptIds) }
                                    .buttonStyle(.plain).font(.caption).foregroundStyle(Color.accentColor)
                                Text("/").foregroundStyle(.tertiary).font(.caption)
                                Button("清空") { selectedDepts.removeAll() }
                                    .buttonStyle(.plain).font(.caption).foregroundStyle(Color.accentColor)
                            }
                            ForEach(panelData.selectedDeptIds, id: \.self) { deptId in
                                let name = panelData.deptNames[deptId] ?? deptId
                                let count = panelData.deptAnsweredCounts[deptId] ?? 0
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

                    if let err = generateError {
                        Label(err, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(20)
            }

            Divider()

            HStack {
                Spacer()
                Button("取消") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isGenerating)
                Button { confirmExport() } label: {
                    if isGenerating {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("正在生成...")
                        }
                        .frame(minWidth: 100)
                    } else {
                        Label("确认导出", systemImage: "square.and.arrow.up")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedDepts.isEmpty || isGenerating)
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 420, height: 540)
    }

    // MARK: - Actions

    private func confirmExport() {
        let config = ExportConfig(
            format: format,
            addFrontmatter: addFrontmatter,
            includeNotes: includeNotes,
            includeAIPolish: includeAIPolish,
            includeVoice: includeVoice,
            includeAIEnhancement: includeAIEnhancement,
            departmentFilter: Array(selectedDepts)
        )
        isGenerating = true
        generateError = nil
        Task {
            if let (content, fileName) = await onGenerate(config) {
                isPresented = false
                onExport(content, fileName)
            } else {
                isGenerating = false
                generateError = "生成失败，请重试"
            }
        }
    }
}
