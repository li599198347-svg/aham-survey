import SwiftUI
import UniformTypeIdentifiers

/// 知识库训练入口 — 显示状态 + 选择文件/文件夹 + 训练进度
struct KnowledgeTrainingView: View {
    @Environment(SettingsManager.self) private var settings
    @State private var trainer = KnowledgeTrainer()
    @State private var manifest: KnowledgeManifest?
    @State private var entryCount: [KnowledgeCategory: Int] = [:]
    @State private var showDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 当前状态
            currentStatus

            Divider()

            // 知识分类概览
            if let manifest, manifest.totalEntries > 0 {
                knowledgeOverview
                Divider()
            }

            // 训练操作
            if trainer.isTraining {
                trainingProgress
            } else {
                trainingActions
            }

            // 错误提示
            if let error = trainer.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onAppear { refreshStatus() }
    }

    // MARK: - 当前状态

    @ViewBuilder
    private var currentStatus: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if let manifest, let lastTrained = manifest.lastTrainedAt {
                    HStack(spacing: 8) {
                        Image(systemName: "brain")
                            .foregroundStyle(.purple)
                        Text("知识库 V\(manifest.version)")
                            .font(.body)
                            .fontWeight(.medium)
                    }
                    Text("最后训练: \(lastTrained, format: .dateTime.year().month().day().hour().minute())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(manifest.totalEntries) 条知识 · \(manifest.processedFiles.count) 个文档已学习")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "brain")
                            .foregroundStyle(.tertiary)
                        Text("知识库未初始化")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    Text("选择行业文档进行首次训练")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if let manifest, manifest.totalEntries > 0 {
                Button {
                    showDetail.toggle()
                } label: {
                    Label("详情", systemImage: "info.circle")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .popover(isPresented: $showDetail) {
                    processedFilesDetail
                }
            }
        }
    }

    // MARK: - 知识概览

    @ViewBuilder
    private var knowledgeOverview: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 6) {
            ForEach(KnowledgeCategory.allCases, id: \.self) { cat in
                let count = entryCount[cat] ?? 0
                if count > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: cat.icon)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(cat.label) \(count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - 训练操作

    @ViewBuilder
    private var trainingActions: some View {
        HStack(spacing: 12) {
            Button {
                selectAndTrain(directory: false)
            } label: {
                Label("选择文件...", systemImage: "doc.badge.plus")
            }

            Button {
                selectAndTrain(directory: true)
            } label: {
                Label("选择文件夹...", systemImage: "folder.badge.plus")
            }

            Spacer()

            Text("支持 TXT、MD、PDF、CSV、JSON")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - 训练进度

    @ViewBuilder
    private var trainingProgress: some View {
        if let prog = trainer.progress {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在训练...")
                        .font(.callout)
                        .fontWeight(.medium)
                }

                ProgressView(
                    value: Double(prog.processedFiles),
                    total: Double(max(prog.totalFiles, 1))
                )

                HStack(spacing: 16) {
                    Text("进度: \(prog.processedFiles)/\(prog.totalFiles)")
                        .font(.caption)
                    Text("跳过: \(prog.skippedFiles)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("新增: \(prog.newEntries)")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text("更新: \(prog.updatedEntries)")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }

                Text("当前: \(prog.currentFile)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - 已处理文件详情

    @ViewBuilder
    private var processedFilesDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("已训练文档")
                .font(.headline)

            if let files = manifest?.processedFiles, !files.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(files) { file in
                            HStack {
                                Image(systemName: "doc.text")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(file.fileName)
                                    .font(.callout)
                                Spacer()
                                Text("\(file.entriesExtracted) 条")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(file.processedAt, format: .dateTime.month().day())
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            } else {
                Text("暂无")
                    .foregroundStyle(.tertiary)
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
            panel.allowedContentTypes = [.plainText, .pdf, .json, .commaSeparatedText, .xml]
        }
        panel.message = directory ? "选择包含行业文档的文件夹" : "选择要训练的文档"

        guard panel.runModal() == .OK else { return }

        var urls: [URL] = []
        if directory, let dir = panel.url {
            // 扫描文件夹中所有支持的文件
            let supportedExts = ["txt", "md", "markdown", "json", "csv", "pdf", "xml", "html"]
            if let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) {
                for case let fileURL as URL in enumerator {
                    if supportedExts.contains(fileURL.pathExtension.lowercased()) {
                        urls.append(fileURL)
                    }
                }
            }
        } else {
            urls = panel.urls
        }

        guard !urls.isEmpty else { return }

        Task {
            await trainer.train(fileURLs: urls, settings: settings)
            refreshStatus()
        }
    }

    private func refreshStatus() {
        manifest = trainer.store.loadManifest()
        let entries = trainer.store.loadEntries()
        var counts: [KnowledgeCategory: Int] = [:]
        for entry in entries {
            counts[entry.category, default: 0] += 1
        }
        entryCount = counts
    }
}
