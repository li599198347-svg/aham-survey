import SwiftUI
import UniformTypeIdentifiers

/// 知识库训练入口 — 文件训练 + 问题重构 + 确认
struct KnowledgeTrainingView: View {
    @Environment(SettingsManager.self) private var settings
    @Environment(PluginLoader.self) private var pluginLoader
    @State private var trainer = KnowledgeTrainer()
    @State private var manifest: KnowledgeManifest?
    @State private var entryCount: [KnowledgeCategory: Int] = [:]
    @State private var supplement: KnowledgeQuestionSupplement?
    @State private var showDetail = false
    @State private var trainTask: Task<Void, Never>?
    @State private var pendingSupplement: KnowledgeQuestionSupplement?
    @State private var showRebuildConfirm = false
    @State private var trainingCompleted = false
    @State private var showQuestionManager = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            currentStatus

            Divider()

            if let manifest, manifest.totalEntries > 0 {
                knowledgeOverview
                Divider()
            }

            if trainer.isTraining {
                trainingProgress
            } else if trainingCompleted {
                trainingCompletionBanner
            } else {
                trainingActions
            }

            if let error = trainer.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            rebuildSection
        }
        .onAppear { refreshStatus() }
        .sheet(isPresented: $showQuestionManager) {
            QuestionManagerView(
                departments: pluginLoader.departments,
                pluginLoader: pluginLoader,
                onDone: { showQuestionManager = false }
            )
        }
        .sheet(isPresented: $showRebuildConfirm) {
            if let pending = pendingSupplement {
                RebuildConfirmSheet(
                    supplement: pending,
                    departments: pluginLoader.departments,
                    onConfirm: { filtered in
                        trainer.confirmRebuild(filtered)
                        pendingSupplement = nil
                        showRebuildConfirm = false
                        refreshStatus()
                    },
                    onCancel: {
                        pendingSupplement = nil
                        showRebuildConfirm = false
                    }
                )
            }
        }
    }

    // MARK: - 当前状态

    @ViewBuilder
    private var currentStatus: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if let manifest, let lastTrained = manifest.lastTrainedAt {
                    HStack(spacing: 8) {
                        Image(systemName: "brain").foregroundStyle(.purple)
                        Text("知识库 V\(manifest.version)")
                            .font(.body).fontWeight(.medium)
                    }
                    Text("最后训练: \(lastTrained, format: .dateTime.year().month().day().hour().minute())")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("\(manifest.totalEntries) 条知识 · \(manifest.processedFiles.count) 个文档已学习")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "brain").foregroundStyle(.tertiary)
                        Text("知识库未初始化").font(.body).foregroundStyle(.secondary)
                    }
                    Text("选择行业文档进行首次训练")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if let manifest, manifest.totalEntries > 0 {
                Button { showDetail.toggle() } label: {
                    Label("详情", systemImage: "info.circle").font(.caption)
                }
                .buttonStyle(.borderless)
                .popover(isPresented: $showDetail) { processedFilesDetail }
            }
        }
    }

    // MARK: - 知识概览

    @ViewBuilder
    private var knowledgeOverview: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 6) {
            ForEach(KnowledgeCategory.allCases, id: \.self) { cat in
                let count = entryCount[cat] ?? 0
                if count > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: cat.icon).font(.caption2).foregroundStyle(.secondary)
                        Text("\(cat.label) \(count)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - 训练完成横幅

    @ViewBuilder
    private var trainingCompletionBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("训练完成").font(.callout).fontWeight(.medium)
                if let prog = trainer.progress {
                    Text("新增 \(prog.newEntries) 条 · 更新 \(prog.updatedEntries) 条 · 跳过 \(prog.skippedFiles) 个文件")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(.green.opacity(0.08), in: .rect(cornerRadius: 8))
    }

    // MARK: - 训练操作

    @ViewBuilder
    private var trainingActions: some View {
        HStack(spacing: 12) {
            Button { selectAndTrain(directory: false) } label: {
                Label("选择文件...", systemImage: "doc.badge.plus")
            }
            Button { selectAndTrain(directory: true) } label: {
                Label("选择文件夹...", systemImage: "folder.badge.plus")
            }
            Spacer()
            Text("支持 TXT·MD·PDF·Word·Excel·PPT 等")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    // MARK: - 训练进度

    @ViewBuilder
    private var trainingProgress: some View {
        if let prog = trainer.progress {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("正在训练...").font(.callout).fontWeight(.medium)
                    Spacer()
                    Button("取消") { trainTask?.cancel(); trainTask = nil }
                        .foregroundStyle(.red).buttonStyle(.borderless)
                }
                ProgressView(value: Double(prog.processedFiles),
                             total: Double(max(prog.totalFiles, 1)))
                HStack(spacing: 16) {
                    Text("进度: \(prog.processedFiles)/\(prog.totalFiles)").font(.caption)
                    Text("跳过: \(prog.skippedFiles)").font(.caption).foregroundStyle(.secondary)
                    Text("新增: \(prog.newEntries)").font(.caption).foregroundStyle(.green)
                    Text("更新: \(prog.updatedEntries)").font(.caption).foregroundStyle(.blue)
                }
                Text("当前: \(prog.currentFile)").font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
    }

    // MARK: - 重构进度

    @ViewBuilder
    private var rebuildProgressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let prog = trainer.rebuildProgress {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("正在生成：\(prog.currentDeptName)")
                        .font(.callout).fontWeight(.medium)
                        .lineLimit(1)
                    Spacer()
                    Text("已收集 \(prog.collectedQuestions) 条")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ProgressView(
                    value: Double(prog.processedDepts),
                    total: Double(max(prog.totalDepts, 1))
                )
                Text("第 \(prog.processedDepts + 1) / \(prog.totalDepts) 个部门")
                    .font(.caption2).foregroundStyle(.tertiary)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("AI 正在生成补充问题，请稍候...")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 问题重构

    @ViewBuilder
    private var rebuildSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars").foregroundStyle(.orange)
                Text("问题重构").font(.body).fontWeight(.medium)
            }

            if let s = supplement {
                Text("V\(s.version) · \(s.generatedAt, format: .dateTime.year().month().day()) · \(s.totalQuestions) 条补充问题")
                    .font(.caption).foregroundStyle(.secondary)
                Text("新建项目将自动加载知识库补充问题")
                    .font(.caption2).foregroundStyle(.tertiary)
            } else {
                Text("尚未生成补充问题").font(.caption).foregroundStyle(.secondary)
                Text("训练知识库后，点击重构为各部门生成额外调研问题")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            if let status = trainer.rebuildStatus {
                Label(status, systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            }

            if trainer.isRebuilding {
                rebuildProgressView
            } else {
                let hasKnowledge = (manifest?.totalEntries ?? 0) > 0
                HStack(spacing: 10) {
                    Button {
                        startRebuild()
                    } label: {
                        Label(supplement == nil ? "生成补充问题" : "重新生成", systemImage: "arrow.clockwise")
                    }
                    .disabled(!hasKnowledge || trainer.isTraining)
                    .help(hasKnowledge ? "基于知识库为各部门生成补充调研问题，生成后需人工确认" : "请先训练知识库")

                    Button {
                        showQuestionManager = true
                    } label: {
                        Label("问题管理", systemImage: "slider.horizontal.3")
                    }
                    .help("浏览并排除不需要的内置问题，排除后新建项目不再包含")
                }
            }
        }
    }

    // MARK: - 已处理文件详情

    @ViewBuilder
    private var processedFilesDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("已训练文档").font(.headline)
            if let files = manifest?.processedFiles, !files.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(files) { file in
                            HStack {
                                Image(systemName: "doc.text").font(.caption).foregroundStyle(.secondary)
                                Text(file.fileName).font(.callout)
                                Spacer()
                                Text("\(file.entriesExtracted) 条").font(.caption).foregroundStyle(.secondary)
                                Text(file.processedAt, format: .dateTime.month().day())
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            } else {
                Text("暂无").foregroundStyle(.tertiary)
            }
        }
        .padding()
        .frame(width: 400)
    }

    // MARK: - 操作

    private func selectAndTrain(directory: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = directory
        panel.canChooseFiles = !directory
        panel.allowsMultipleSelection = !directory
        if !directory {
            // 支持所有常见办公文档格式
            let exts = FileTextExtractor.supportedExtensions
            panel.allowedContentTypes = exts.compactMap { UTType(filenameExtension: $0) }
        }
        panel.message = directory ? "选择包含行业文档的文件夹" : "选择要训练的文档"

        panel.begin { [self] response in
            guard response == .OK else { return }

            var urls: [URL] = []
            if directory, let dir = panel.url {
                let supported = FileTextExtractor.supportedExtensions
                if let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) {
                    for case let fileURL as URL in enumerator {
                        if supported.contains(fileURL.pathExtension.lowercased()) {
                            urls.append(fileURL)
                        }
                    }
                }
            } else {
                urls = panel.urls
            }

            guard !urls.isEmpty else { return }
            trainTask?.cancel()
            trainTask = Task {
                await trainer.train(fileURLs: urls, settings: settings)
                trainingCompleted = true
                try? await Task.sleep(for: .seconds(2))
                trainingCompleted = false
                refreshStatus()
            }
        }
    }

    private func startRebuild() {
        Task {
            let result = await trainer.rebuildQuestions(
                departments: pluginLoader.departments,
                settings: settings
            )
            if let s = result {
                pendingSupplement = s
                showRebuildConfirm = true
            }
        }
    }

    private func refreshStatus() {
        manifest = trainer.store.loadManifest()
        supplement = trainer.questionStore.load()
        let entries = trainer.store.loadEntries()
        var counts: [KnowledgeCategory: Int] = [:]
        for entry in entries { counts[entry.category, default: 0] += 1 }
        entryCount = counts
    }
}

// MARK: - 重构确认 Sheet

private struct RebuildConfirmSheet: View {
    let supplement: KnowledgeQuestionSupplement
    let departments: [DepartmentTemplate]
    let onConfirm: (KnowledgeQuestionSupplement) -> Void
    let onCancel: () -> Void

    @State private var expandedDepts: Set<String> = []
    @State private var selectedIds: Set<String> = []

    private var allIds: Set<String> {
        Set(supplement.supplements.values.flatMap { $0.map(\.id) })
    }
    private var isAllSelected: Bool { selectedIds == allIds }
    private var selectedCount: Int { selectedIds.count }

    private var deptNameMap: [String: String] {
        Dictionary(uniqueKeysWithValues: departments.map { ($0.id, $0.name) })
    }

    // 按部门ID排序的补充条目
    private var sortedEntries: [(deptId: String, deptName: String, questions: [QuestionTemplate])] {
        supplement.supplements
            .map { (deptId: $0.key,
                    deptName: deptNameMap[$0.key] ?? $0.key,
                    questions: $0.value) }
            .sorted { $0.deptName < $1.deptName }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("确认问题更新")
                        .font(.title2).fontWeight(.semibold)
                    Text("本次为 \(sortedEntries.count) 个部门生成了共 \(supplement.totalQuestions) 条补充问题")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("已选 \(selectedCount) / 共 \(allIds.count) 条")
                        .font(.caption).foregroundStyle(.secondary)
                    Button(isAllSelected ? "全部取消" : "全选") {
                        selectedIds = isAllSelected ? [] : allIds
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
            }
            .padding()
            .onAppear { selectedIds = allIds }

            Divider()

            // 问题清单
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sortedEntries, id: \.deptId) { entry in
                        deptSection(entry)
                    }
                }
                .padding()
            }

            Divider()

            // 说明 + 操作按钮
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary).font(.caption)
                    Text("确认后，**新建项目**将自动加载这些补充问题；已有项目不受影响")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Button("取消", role: .cancel) { onCancel() }
                    Spacer()
                    Button("确认应用 (\(selectedCount) 条)") {
                        let filteredSupplements = supplement.supplements.compactMapValues { questions -> [QuestionTemplate]? in
                            let filtered = questions.filter { selectedIds.contains($0.id) }
                            return filtered.isEmpty ? nil : filtered
                        }
                        let filtered = KnowledgeQuestionSupplement(
                            version: supplement.version,
                            generatedAt: supplement.generatedAt,
                            totalQuestions: selectedCount,
                            supplements: filteredSupplements
                        )
                        onConfirm(filtered)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedCount == 0)
                }
            }
            .padding()
        }
        .frame(width: 560, height: 480)
    }

    @ViewBuilder
    private func deptSection(_ entry: (deptId: String, deptName: String, questions: [QuestionTemplate])) -> some View {
        let isExpanded = expandedDepts.contains(entry.deptId)

        VStack(alignment: .leading, spacing: 0) {
            // 部门行（可展开/收起）
            Button {
                if isExpanded { expandedDepts.remove(entry.deptId) }
                else { expandedDepts.insert(entry.deptId) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption).foregroundStyle(.secondary).frame(width: 12)
                    Text(entry.deptName).font(.callout).fontWeight(.medium)
                    Text("\(entry.questions.count) 条")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.secondary.opacity(0.12), in: .capsule)
                    Spacer()
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            // 问题列表（展开时显示）
            if isExpanded {
                ForEach(entry.questions) { q in
                    HStack(alignment: .top, spacing: 10) {
                        Toggle("", isOn: Binding(
                            get: { selectedIds.contains(q.id) },
                            set: { on in
                                if on { selectedIds.insert(q.id) }
                                else { selectedIds.remove(q.id) }
                            }
                        ))
                        .toggleStyle(.checkbox)
                        .labelsHidden()

                        Text(q.section.label)
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(sectionColor(q.section).opacity(0.12), in: .capsule)
                            .foregroundStyle(sectionColor(q.section))
                            .frame(width: 54, alignment: .center)

                        Text(q.question)
                            .font(.callout)
                            .foregroundStyle(selectedIds.contains(q.id) ? .primary : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, 20)
                    .padding(.vertical, 5)
                }
            }

            Divider().padding(.leading, 20)
        }
    }

    private func sectionColor(_ section: QuestionSection) -> Color {
        switch section {
        case .opening:    return .blue
        case .process:    return .teal
        case .painpoint:  return .orange
        case .expectation: return .purple
        case .compliance: return .green
        }
    }
}
