import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ProjectDetailView: View {
    @Bindable var project: Project
    @Environment(AppStore.self) private var appStore
    @Environment(SettingsManager.self) private var settings
    @Environment(PluginLoader.self) private var pluginLoader
    @Query private var allAnswers: [Answer]

    @State private var docAnalyzer = ProjectDocumentAnalyzer()
    @State private var analysisResult: ProjectDocumentAnalyzer.DocumentAnalysisResult?
    @State private var showExportPanel = false
    @State private var isEditingInfo = false
    @State private var isExportingToObsidian = false
    @State private var obsidianExportMessage: String?
    @State private var aiEnhancer: AIProjectEnhancer?
    @State private var isSearchingProductInfo = false

    private var projectAnswers: [Answer] {
        allAnswers.filter { $0.projectId == project.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 项目头部
                projectHeader

                // 操作按钮
                actionSection

                // 两列布局：客户信息（左）| AI 增强 + 调研配置（右堆叠）
                HStack(alignment: .top, spacing: 16) {
                    customerInfoSection
                        .frame(maxWidth: .infinity)
                    VStack(spacing: 16) {
                        aiEnhancementSection
                        surveyConfigSection
                    }
                    .frame(maxWidth: .infinity)
                }

                // 进度概览
                if !project.selectedDepartmentIds.isEmpty {
                    progressSection
                }
            }
            .padding(24)
        }
        .navigationTitle(project.displayName)
        .onAppear { syncProgress() }
        .toolbar {
            ToolbarItem {
                Menu {
                    statusMenuItems
                } label: {
                    Label(project.status.label, systemImage: project.status.icon)
                }
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var projectHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(statusGradient)
                    .frame(width: 64, height: 64)
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(project.displayName)
                    .font(.title)
                    .fontWeight(.bold)

                HStack(spacing: 16) {
                    if !project.consultant.isEmpty {
                        Label(project.consultant, systemImage: "person.fill")
                    }
                    Label {
                        Text(project.surveyDate, format: .dateTime.year().month().day())
                    } icon: {
                        Image(systemName: "calendar")
                    }

                    HStack(spacing: 4) {
                        Image(systemName: project.status.icon)
                        Text(project.status.label)
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.12), in: .capsule)
                    .foregroundStyle(statusColor)
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Label(project.industryEnum.label, systemImage: project.industryEnum.icon)
                    if !project.surveyScopes.isEmpty {
                        Label(project.surveyScopes.map(\.label).joined(separator: "+"), systemImage: "scope")
                    }
                    if !project.selectedDepartmentIds.isEmpty {
                        Label("\(project.selectedDepartmentIds.count) 个部门", systemImage: "building.2")
                    }
                    if project.totalQuestions > 0 {
                        Label("\(project.totalQuestions) 道题", systemImage: "list.bullet.rectangle")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Action Section

    @ViewBuilder
    private var actionSection: some View {
        HStack(spacing: 12) {
            if project.status == .draft {
                Button {
                    project.status = .inProgress
                    project.updatedAt = .now
                    appStore.isSurveying = true
                } label: {
                    Label("开始调研", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            if project.status == .inProgress {
                Button {
                    appStore.isSurveying = true
                } label: {
                    let pct = Int(project.progress * 100)
                    Label("继续调研 (\(pct)%)", systemImage: "arrow.right.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            if project.status == .completed {
                Label("调研已完成", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            }

            Spacer()

            if project.answeredQuestions > 0 {
                // Obsidian 直接导出（仅配置了 vault 路径时显示）
                if !settings.obsidianConfig.vaultPath.isEmpty {
                    VStack(alignment: .trailing, spacing: 3) {
                        Button {
                            exportToObsidian()
                        } label: {
                            if isExportingToObsidian {
                                HStack(spacing: 5) {
                                    ProgressView().controlSize(.mini)
                                    Text("写入中...")
                                }
                            } else {
                                Label("导出到 Obsidian", systemImage: "note.text")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isExportingToObsidian)

                        if let msg = obsidianExportMessage {
                            Text(msg)
                                .font(.caption2)
                                .foregroundStyle(msg.hasPrefix("✅") ? Color.green : Color.red)
                                .transition(.opacity)
                        }
                    }
                }

                // 导出报告（选项面板）
                Button {
                    showExportPanel = true
                } label: {
                    Label("导出报告", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .sheet(isPresented: $showExportPanel) {
                    ExportPanelView(
                        panelData: buildExportPanelData(),
                        isPresented: $showExportPanel,
                        onGenerate: { config in
                            let snapshot = self.buildExportSnapshot()
                            let baseName = "\(snapshot.displayName) 调研报告"
                            switch config.format {
                            case .markdown:
                                guard let data = MarkdownExporter.exportProject(snapshot: snapshot, config: config).data(using: .utf8) else { return nil }
                                return (data, "\(baseName).md")
                            case .word:
                                guard let data = await MarkdownExporter.exportProjectAsDOCX(snapshot: snapshot, config: config) else { return nil }
                                return (data, "\(baseName).docx")
                            }
                        },
                        onExport: { data, name in
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                self.saveExportFile(data: data, fileName: name)
                            }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Customer Info + Document Import

    @ViewBuilder
    private var customerInfoSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                if isEditingInfo {
                    editableInfoRow("客户名称", $project.customerName)
                    Picker("组织形态", selection: Binding(
                        get: { OrgScale(rawValue: project.companyScale) ?? .unset },
                        set: { project.companyScale = $0.rawValue }
                    )) {
                        ForEach(OrgScale.allCases, id: \.self) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    Picker("员工规模", selection: Binding(
                        get: { StaffScale(rawValue: project.headcount) ?? .unset },
                        set: { project.headcount = $0.rawValue }
                    )) {
                        ForEach(StaffScale.allCases, id: \.self) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    Picker("年营收", selection: Binding(
                        get: { RevenueScale(rawValue: project.revenue) ?? .unset },
                        set: { project.revenue = $0.rawValue }
                    )) {
                        ForEach(RevenueScale.allCases, id: \.self) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    editableInfoRow("现有系统", $project.existingSystems)
                } else {
                    infoRow("客户名称", project.customerName, icon: "building.2.fill")
                    if !project.companyScale.isEmpty {
                        infoRow("组织形态", project.companyScale, icon: "building.2")
                    }
                    if !project.headcount.isEmpty {
                        infoRow("员工规模", project.headcount, icon: "person.3.fill")
                    }
                    if !project.revenue.isEmpty {
                        infoRow("年营收", project.revenue, icon: "yensign.circle.fill")
                    }
                    if !project.existingSystems.isEmpty {
                        infoRow("现有系统", project.existingSystems, icon: "server.rack")
                    }

                    let hasAnyInfo = !project.companyScale.isEmpty || !project.headcount.isEmpty
                        || !project.revenue.isEmpty || !project.existingSystems.isEmpty
                    if !hasAnyInfo {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.tertiary)
                            Text("点击「编辑」补充客户信息")
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.top, 2)
                    }
                }

                // 产品与工艺
                Divider()
                productInfoArea

                // 文档导入
                Divider()
                documentImportArea
            }
        } label: {
            HStack(spacing: 8) {
                Label("客户信息", systemImage: "person.text.rectangle")
                    .font(.headline)
                Spacer()
                Button(isEditingInfo ? "完成" : "编辑") {
                    isEditingInfo.toggle()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Product Info

    @ViewBuilder
    private var productInfoArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "shippingbox")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor.opacity(0.6))
                Text("产品与工艺")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if isSearchingProductInfo {
                    ProgressView()
                        .controlSize(.mini)
                } else if !project.customerName.isEmpty {
                    Button {
                        searchProductInfo()
                    } label: {
                        Label("AI 搜索", systemImage: "magnifyingglass")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(!settings.isLLMConfigured)
                }
            }
            TextEditor(text: $project.productInfo)
                .font(.callout)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 50, maxHeight: 100)
                .padding(6)
                .background(Color.yellow.opacity(0.05), in: .rect(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.fill.tertiary, lineWidth: 0.5)
                )
            if project.productInfo.isEmpty {
                Text("填写或 AI 搜索客户的主要产品和生产工艺")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
        }
    }

    private func searchProductInfo() {
        guard let provider = settings.llmProvider, !project.customerName.isEmpty else { return }
        isSearchingProductInfo = true
        Task {
            let messages = [
                LLMMessage(role: .system, content: "根据公司名称，简要描述该公司的主要产品、生产工艺和业务范围。用中文，3-5句话。如果不确定，注明是推测。"),
                LLMMessage(role: .user, content: "公司名称：\(project.customerName)")
            ]
            do {
                let result = try await provider.chat(messages: messages, options: .default)
                project.productInfo = result
            } catch {
                project.productInfo = "搜索失败：\(error.localizedDescription)"
            }
            isSearchingProductInfo = false
        }
    }

    // MARK: - Document Import (inline)

    @ViewBuilder
    private var documentImportArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            if docAnalyzer.isAnalyzing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在分析文档...")
                        .font(.callout)
                }
            } else if let result = analysisResult {
                if !result.keyFindings.isEmpty {
                    Text("关键发现")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(result.keyFindings, id: \.self) { finding in
                        Label(finding, systemImage: "lightbulb")
                            .font(.callout)
                    }
                }
                if !result.knownIssues.isEmpty {
                    Text("已知问题")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(result.knownIssues, id: \.self) { issue in
                        Label(issue, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                    }
                }
                if !result.knownNeeds.isEmpty {
                    Text("已知需求")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(result.knownNeeds, id: \.self) { need in
                        Label(need, systemImage: "star")
                            .font(.callout)
                    }
                }

                Button("应用到项目") {
                    docAnalyzer.applyToProject(result, project: project)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(spacing: 8) {
                Button {
                    importDocument()
                } label: {
                    Label("导入客户文档...", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(docAnalyzer.isAnalyzing)

                Text("AI 自动提取客户画像和已知信息")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                if let error = docAnalyzer.lastError {
                    HStack(spacing: 4) {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                        Button {
                            docAnalyzer.lastError = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Survey Config

    @ViewBuilder
    private var surveyConfigSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                // 调研范围
                if !project.surveyScopes.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "scope")
                            .font(.callout)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 18)
                        Text(project.surveyScopes.map(\.label).joined(separator: " + "))
                            .font(.callout)
                    }
                }

                if !project.selectedDepartmentIds.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("调研部门")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(
                            pluginLoader.selectedDepartments(ids: project.selectedDepartmentIds)
                                .map(\.name)
                                .joined(separator: " · ")
                        )
                        .font(.callout)
                        .foregroundStyle(.primary)
                    }
                }
            }
        } label: {
            Label("调研配置", systemImage: "gearshape.fill")
                .font(.headline)
        }
    }

    // MARK: - Progress

    @ViewBuilder
    private var progressSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("已完成 \(project.answeredQuestions) / \(project.totalQuestions) 题")
                        .font(.callout)
                    Spacer()
                    Text("\(Int(project.progress * 100))%")
                        .font(.title3)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundStyle(project.progress >= 1 ? .green : Color.accentColor)
                }
                ProgressView(value: project.progress)
                    .tint(project.progress >= 1.0 ? .green : Color.accentColor)

                if project.selectedDepartmentIds.count > 1 {
                    Divider()
                    Text("各部门详情")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    let filteredByDept = pluginLoader.questionsForProject(project)
                    ForEach(pluginLoader.selectedDepartments(ids: project.selectedDepartmentIds)) { dept in
                        let total = filteredByDept[dept.id]?.count ?? 0
                        let done = projectAnswers.filter { $0.departmentId == dept.id && $0.hasContent }.count
                        let pct = total > 0 ? Double(done) / Double(total) : 0

                        Button {
                            appStore.isSurveying = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: dept.sfSymbol)
                                    .font(.caption)
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 16)
                                Text(dept.name)
                                    .font(.callout)
                                    .frame(width: 80, alignment: .leading)
                                ProgressView(value: pct)
                                    .tint(pct >= 1 ? .green : Color.accentColor)
                                Text("\(done)/\(total)")
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } label: {
            Label("调研进度", systemImage: "chart.bar.fill")
                .font(.headline)
        }
    }

    // MARK: - AI Enhancement Status

    @ViewBuilder
    private var aiEnhancementSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                // 优先检查 isEnhancing，确保"重新生成"时能显示进度
                if let enhancer = aiEnhancer, enhancer.isEnhancing {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(enhancer.progress)
                                .font(.callout)
                            Spacer()
                            Text("\(Int(enhancer.progressFraction * 100))%")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: enhancer.progressFraction)
                            .tint(.purple)
                    }
                } else if let enhancement = project.aiEnhancement {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("AI 增强已完成")
                            .font(.callout)
                            .fontWeight(.medium)
                        Spacer()
                        Text(enhancement.generatedAt, format: .dateTime.month().day().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    HStack(spacing: 16) {
                        if !enhancement.optionSets.isEmpty {
                            Label("\(enhancement.optionSets.count) 个动态选项", systemImage: "list.bullet")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !enhancement.priorityAdjustments.isEmpty {
                            Label("\(enhancement.priorityAdjustments.count) 个优先级调整", systemImage: "arrow.up.arrow.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !enhancement.skipSuggestions.isEmpty {
                            Label("\(enhancement.skipSuggestions.count) 个跳过建议", systemImage: "forward.end")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !enhancement.additionalQuestions.isEmpty {
                            Label("\(enhancement.additionalQuestions.count) 个补充问题", systemImage: "plus.bubble")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !enhancement.industryContext.isEmpty {
                        Text(enhancement.industryContext)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }

                    Button("重新生成") {
                        runAIEnhancement()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                            .foregroundStyle(.purple)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AI 智能增强")
                                .font(.callout)
                                .fontWeight(.medium)
                            Text("根据客户属性和行业特征，自动生成动态选项、调整优先级")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("生成") {
                            runAIEnhancement()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!settings.isLLMConfigured)
                    }

                    if let enhancer = aiEnhancer, let error = enhancer.lastError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        } label: {
            Label("AI 增强", systemImage: "wand.and.stars")
                .font(.headline)
        }
    }

    private func runAIEnhancement() {
        let enhancer = AIProjectEnhancer(settings: settings)
        self.aiEnhancer = enhancer

        // 按部门收集问题
        let questionsByDept = pluginLoader.questionsForProject(project)

        Task {
            if let result = await enhancer.enhance(project: project, questionsByDept: questionsByDept) {
                project.aiEnhancement = result
                project.updatedAt = .now
            }
        }
    }

    // MARK: - Export

    /// 在 MainActor 上将所有 @Model / @Observable 数据复制为纯值类型快照
    private func buildExportSnapshot() -> ExportSnapshot {
        let answers = projectAnswers

        // 构建 departmentSections：纯值类型，不持有任何 @Model 引用
        var deptNames: [String: String] = [:]
        var deptSections: [String: [ExportSnapshot.ExportSectionData]] = [:]

        for deptId in project.selectedDepartmentIds {
            let dept = pluginLoader.departments.first { $0.id == deptId }
            deptNames[deptId] = dept?.name ?? deptId

            let deptAnswers = answers.filter { $0.departmentId == deptId }
            let rawSections = pluginLoader.questionsBySection(for: deptId)

            let sections: [ExportSnapshot.ExportSectionData] = rawSections.map { (section, questions) in
                let items: [ExportSnapshot.ExportItem] = questions.map { q in
                    let ans = deptAnswers.first { $0.questionId == q.id }
                    return ExportSnapshot.ExportItem(
                        topic: q.topic,
                        question: q.question,
                        selectedOptions: ans?.selectedOptions ?? [],
                        textValue: ans?.textValue ?? "",
                        noteText: ans?.noteText ?? "",
                        polishedText: ans?.polishedText ?? "",
                        voiceTranscript: ans?.voiceTranscript ?? "",
                        hasContent: ans?.hasContent ?? false
                    )
                }
                return ExportSnapshot.ExportSectionData(label: section.label, items: items)
            }
            deptSections[deptId] = sections
        }

        return ExportSnapshot(
            displayName: project.displayName,
            customerName: project.customerName,
            consultant: project.consultant,
            surveyDate: project.surveyDate,
            statusLabel: project.status.label,
            industryLabel: project.industryEnum.label,
            companyScale: project.companyScale,
            headcount: project.headcount,
            revenue: project.revenue,
            existingSystems: project.existingSystems,
            surveyGoal: project.surveyGoal,
            totalQuestions: project.totalQuestions,
            answeredQuestions: project.answeredQuestions,
            progress: project.progress,
            aiEnhancement: project.aiEnhancement,
            selectedDepartmentIds: project.selectedDepartmentIds,
            departmentNames: deptNames,
            departmentSections: deptSections
        )
    }

    /// 全程在主线程完成：NSSavePanel.begin（非阻塞）+ 文件写入，无后台 Task
    private func saveExportFile(data: Data, fileName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileName
        panel.canCreateDirectories = true
        if fileName.hasSuffix(".md") {
            panel.allowedContentTypes = [.plainText]
            panel.message = "选择 Markdown 导出位置"
        } else {
            panel.allowedContentTypes = [UTType(filenameExtension: "docx") ?? .data]
            panel.message = "选择 Word 文档导出位置"
        }
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                print("[Export] 写入失败: \(error)")
            }
        }
    }

    private func importDocument() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, .pdf, .json]
        panel.message = "选择客户提供的文档"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task {
                self.analysisResult = await self.docAnalyzer.analyze(fileURL: url, settings: self.settings)
            }
        }
    }

    // MARK: - Status Menu

    @ViewBuilder
    private var statusMenuItems: some View {
        ForEach(ProjectStatus.allCases, id: \.self) { status in
            Button {
                project.status = status
                project.updatedAt = .now
            } label: {
                Label(status.label, systemImage: status.icon)
            }
            .disabled(project.status == status)
        }
    }

    // MARK: - Helpers

    /// 构建轻量面板数据（快速，仅读部门名和答题数）
    private func buildExportPanelData() -> ExportPanelData {
        var deptNames: [String: String] = [:]
        var deptCounts: [String: Int] = [:]
        for deptId in project.selectedDepartmentIds {
            let dept = pluginLoader.departments.first { $0.id == deptId }
            deptNames[deptId] = dept?.name ?? deptId
            deptCounts[deptId] = projectAnswers.filter { $0.departmentId == deptId && $0.hasContent }.count
        }
        return ExportPanelData(
            projectName: project.displayName,
            selectedDeptIds: project.selectedDepartmentIds,
            deptNames: deptNames,
            deptAnsweredCounts: deptCounts,
            hasAIEnhancement: project.aiEnhancement != nil
        )
    }

    /// 直接写入 Obsidian vault（非沙盒 app，直接使用存储的路径）
    private func exportToObsidian() {
        let vaultPath = settings.obsidianConfig.vaultPath
        guard !vaultPath.isEmpty else {
            obsidianExportMessage = "❌ 请先在设置中选择 Obsidian Vault 目录"
            return
        }

        isExportingToObsidian = true
        obsidianExportMessage = nil

        let snapshot = buildExportSnapshot()
        let vaultURL = URL(fileURLWithPath: vaultPath)

        Task {
            let content = MarkdownExporter.exportProject(snapshot: snapshot, config: .default)
            let folderURL = vaultURL.appendingPathComponent("调研报告")
            let fileURL = folderURL.appendingPathComponent("\(snapshot.displayName) 调研报告.md")

            do {
                try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
                isExportingToObsidian = false
                withAnimation { obsidianExportMessage = "✅ 已写入 Obsidian" }
                try? await Task.sleep(for: .seconds(2))
                withAnimation {
                    if obsidianExportMessage?.hasPrefix("✅") == true {
                        obsidianExportMessage = nil
                    }
                }
            } catch {
                isExportingToObsidian = false
                withAnimation { obsidianExportMessage = "❌ 写入失败: \(error.localizedDescription)" }
            }
        }
    }

    private func syncProgress() {
        let selectedDepts = Set(project.selectedDepartmentIds)
        let total = pluginLoader.questionsForProject(project).values.reduce(0) { $0 + $1.count }
        let answered = projectAnswers.filter { selectedDepts.contains($0.departmentId) && $0.hasContent }.count
        project.totalQuestions = total
        project.answeredQuestions = answered
        project.progress = total > 0 ? Double(answered) / Double(total) : 0
    }

    private func infoRow(_ label: String, _ value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Color.accentColor.opacity(0.6))
                .frame(width: 16)
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            Text(value.isEmpty ? "—" : value)
                .font(.callout)
                .foregroundStyle(value.isEmpty ? .tertiary : .primary)
        }
    }

    private func editableInfoRow(_ label: String, _ binding: Binding<String>) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            TextField(label, text: binding)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
        }
    }

    private var statusColor: Color {
        switch project.status {
        case .draft: .gray
        case .inProgress: .blue
        case .completed: .green
        case .archived: .secondary
        }
    }

    private var statusGradient: LinearGradient {
        switch project.status {
        case .draft:
            LinearGradient(colors: [.gray, .gray.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .inProgress:
            LinearGradient(colors: [.blue, .blue.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .completed:
            LinearGradient(colors: [.green, .green.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .archived:
            LinearGradient(colors: [.gray, .gray.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

/// 简易流式布局（用于部门标签展示）
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
