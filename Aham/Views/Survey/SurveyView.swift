import SwiftUI
import SwiftData

/// 调研主界面：顶部部门 Tab + 左侧问题导航 + 中间聚焦问题 + 右侧录音/AI
struct SurveyView: View {
    @Bindable var project: Project
    @Environment(PluginLoader.self) var pluginLoader
    @Environment(\.modelContext) var modelContext
    @Query var allAnswers: [Answer]

    @Environment(VoiceManager.self) var voiceManager

    @Environment(SettingsManager.self) var settings

    @State var selectedDepartmentId: String?
    @State var focusedQuestionIndex: Int = 0

    // AI 润色 & 追问
    @State var enhancer: AISurveyEnhancer?
    @State var polishStatus: PolishStatus = .idle
    @State var polishTask: Task<Void, Never>?
    @State var followups: [AISurveyEnhancer.FollowupQuestion] = []
    @State var isLoadingFollowups = false
    @State var followupTask: Task<Void, Never>?

    // 录音停止后保存的最后转写文本（speech.transcript 会被清空）
    @State var lastTranscript: String = ""

    // 底部备忘录
    @State var memoExpanded = false
    @State var memoItems: [MemoCategory: [String]] = [
        .forms: [], .metrics: [], .approvals: [], .needs: []
    ]
    @State var newMemoText = ""
    @State var activeMemoCategory: MemoCategory = .forms

    // 已采纳的追问
    @State var adoptedFollowups: [AdoptedFollowup] = []

    // 缓存：答案查找字典，避免每次 O(n) 过滤
    @State var answerLookup: [String: Answer] = [:]

    // 缓存：当前部门的显示问题列表和追问 ID 集合
    @State var cachedDisplayQuestions: [QuestionTemplate] = []
    @State var cachedFollowupIds: Set<String> = []

    private var currentQuestions: [QuestionTemplate] {
        guard let deptId = selectedDepartmentId else { return [] }
        return pluginLoader.questions(for: deptId, scopes: project.surveyScopes, industry: project.industryEnum)
    }

    private var currentSections: [(section: QuestionSection, questions: [QuestionTemplate])] {
        guard let deptId = selectedDepartmentId else { return [] }
        let questions = pluginLoader.questions(for: deptId, scopes: project.surveyScopes, industry: project.industryEnum)
        var result: [(QuestionSection, [QuestionTemplate])] = []
        for section in QuestionSection.allCases {
            let sectionQuestions = questions.filter { $0.section == section }
            if !sectionQuestions.isEmpty {
                result.append((section, sectionQuestions))
            }
        }
        return result
    }

    /// AI 可用性（有 API key 配置）
    var isAIAvailable: Bool { settings.isLLMConfigured }

    /// 录音可用性（有麦克风权限）
    var isRecordingAvailable: Bool { voiceManager.permissionGranted }

    /// 获取追问的父问题文本
    private func parentQuestionText(for questionId: String) -> String? {
        guard let fu = adoptedFollowups.first(where: { $0.template.id == questionId }) else { return nil }
        return cachedDisplayQuestions.first(where: { $0.id == fu.parentQuestionId })?.question
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            departmentTabBar

            Divider()

            HStack(spacing: 0) {
                questionNavSidebar
                    .frame(width: 210)

                Divider()

                questionFocusArea
                    .frame(maxWidth: .infinity)

                Divider()

                surveyRightPanel
                    .frame(width: 280)
            }
        }
        .onAppear {
            if selectedDepartmentId == nil,
               let first = project.selectedDepartmentIds.first {
                selectedDepartmentId = first
            }
            rebuildAnswerLookup()
            ensureAnswersExist()
            rebuildDisplayQuestions()
            // 自动检查权限（不再依赖项目配置）
            Task { await voiceManager.checkPermissions() }
        }
        .onDisappear {
            polishTask?.cancel()
            followupTask?.cancel()
        }
        .onChange(of: selectedDepartmentId) {
            focusedQuestionIndex = 0
            resetAIState()
            ensureAnswersExist()
            rebuildDisplayQuestions()
        }
        .onChange(of: allAnswers.count) {
            rebuildAnswerLookup()
        }
        .onChange(of: focusedQuestionIndex) { _, _ in
            resetAIState()
        }
        // 实时转写变化时，自动触发 AI 润色（录音全程开启模式）
        .onChange(of: voiceManager.speech.transcript) {
            guard voiceManager.state == .recording,
                  focusedQuestionIndex < cachedDisplayQuestions.count else { return }
            let q = cachedDisplayQuestions[focusedQuestionIndex]
            let deptId = selectedDepartmentId ?? ""
            if let answer = findAnswer(for: q.id, departmentId: deptId) {
                scheduleAIPolish(question: q, answer: answer)
            }
        }
    }

    // MARK: - 顶部部门 Tab 栏

    @ViewBuilder
    private var departmentTabBar: some View {
        let departments = pluginLoader.selectedDepartments(ids: project.selectedDepartmentIds)
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(departments) { dept in
                        let isSelected = selectedDepartmentId == dept.id
                        let deptTotal = pluginLoader.questions(for: dept.id).count
                        let deptDone = answeredCount(for: dept.id)

                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedDepartmentId = dept.id
                            }
                        } label: {
                            VStack(spacing: 3) {
                                HStack(spacing: 4) {
                                    Image(systemName: dept.sfSymbol)
                                        .font(.system(size: 10))
                                    Text(dept.name)
                                        .font(.subheadline)
                                        .fontWeight(isSelected ? .medium : .regular)
                                }
                                .foregroundStyle(isSelected ? .primary : .secondary)

                                Text("\(deptDone)/\(deptTotal)")
                                    .font(.system(size: 9))
                                    .monospacedDigit()
                                    .foregroundStyle(
                                        deptDone == deptTotal && deptTotal > 0 ? Color.green : Color.secondary
                                    )
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .overlay(alignment: .bottom) {
                                if isSelected {
                                    Rectangle()
                                        .fill(Color.accentColor)
                                        .frame(height: 2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 8)
            }

            Spacer(minLength: 4)

            // AI 和录音状态指示器
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(isAIAvailable ? Color.green : Color.gray)
                        .frame(width: 6, height: 6)
                    Text("AI")
                        .font(.caption2)
                        .foregroundStyle(isAIAvailable ? Color.primary : Color.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isAIAvailable ? Color.green.opacity(0.08) : Color.gray.opacity(0.08), in: .capsule)
                .help(isAIAvailable ? "AI 已连接" : "请在设置中配置 API Key")

                HStack(spacing: 4) {
                    Circle()
                        .fill(
                            voiceManager.state == .recording ? Color.red :
                            isRecordingAvailable ? Color.green : Color.gray
                        )
                        .frame(width: 6, height: 6)
                    Image(systemName: voiceManager.state == .recording ? "mic.fill" : "mic")
                        .font(.caption2)
                        .foregroundStyle(
                            voiceManager.state == .recording ? Color.red :
                            isRecordingAvailable ? Color.primary : Color.secondary
                        )
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    voiceManager.state == .recording ? Color.red.opacity(0.08) :
                    isRecordingAvailable ? Color.green.opacity(0.08) : Color.gray.opacity(0.08),
                    in: .capsule
                )
                .help(
                    voiceManager.state == .recording ? "正在录音" :
                    isRecordingAvailable ? "麦克风已就绪" : "请授予麦克风权限"
                )
            }
            .padding(.trailing, 12)
        }
        .background(.bar)
    }

    // MARK: - 左侧问题导航

    @ViewBuilder
    private var questionNavSidebar: some View {
        VStack(spacing: 0) {
            // 部门标题
            if let deptId = selectedDepartmentId,
               let dept = pluginLoader.departments.first(where: { $0.id == deptId }) {
                HStack(spacing: 6) {
                    Image(systemName: dept.sfSymbol)
                        .foregroundStyle(Color.accentColor)
                    Text(dept.name)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)

                Divider()
            }

            ScrollViewReader { proxy in
                List {
                    ForEach(currentSections, id: \.section) { section, questions in
                        Section {
                            ForEach(Array(questions.enumerated()), id: \.element.id) { _, question in
                                sidebarQuestionRow(question: question)

                                // 显示该问题下的已采纳追问
                                let deptId = selectedDepartmentId ?? ""
                                let childFollowups = adoptedFollowups.filter {
                                    $0.parentQuestionId == question.id && $0.departmentId == deptId
                                }
                                ForEach(childFollowups) { fu in
                                    sidebarQuestionRow(question: fu.template, isFollowup: true)
                                }
                            }
                        } header: {
                            HStack(spacing: 4) {
                                Image(systemName: section.icon)
                                    .font(.caption2)
                                    .foregroundStyle(section == .painpoint ? .red : .accentColor)
                                Text(section.label)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Spacer()
                                // 小进度
                                let sectionDone = questions.filter { q in
                                    let a = findAnswer(for: q.id, departmentId: selectedDepartmentId ?? "")
                                    return a?.hasContent ?? false
                                }.count
                                if sectionDone > 0 {
                                    Text("\(sectionDone)/\(questions.count)")
                                        .font(.system(size: 9))
                                        .monospacedDigit()
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.sidebar)
                .onChange(of: focusedQuestionIndex) {
                    if focusedQuestionIndex < cachedDisplayQuestions.count {
                        let q = cachedDisplayQuestions[focusedQuestionIndex]
                        withAnimation {
                            proxy.scrollTo(q.id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sidebarQuestionRow(question: QuestionTemplate, isFollowup: Bool = false) -> some View {
        let globalIndex = globalQuestionIndex(for: question)
        let answer = findAnswer(for: question.id, departmentId: selectedDepartmentId ?? "")
        let isFocused = focusedQuestionIndex == globalIndex

        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                focusedQuestionIndex = globalIndex
            }
        } label: {
            HStack(spacing: 6) {
                if isFollowup {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 8))
                        .foregroundStyle(.orange)
                }
                Circle()
                    .fill(statusColor(for: answer))
                    .frame(width: 6, height: 6)

                Text(question.question)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(isFocused ? .primary : .secondary)
                    .fontWeight(isFocused ? .medium : .regular)

                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .padding(.leading, isFollowup ? 12 : 0)
            .background(
                isFocused
                    ? (isFollowup ? Color.orange : Color.accentColor).opacity(0.12)
                    : Color.clear,
                in: .rect(cornerRadius: 4)
            )
        }
        .buttonStyle(.plain)
        .id(question.id)
    }

    // MARK: - 中间聚焦问题区

    @ViewBuilder
    private var questionFocusArea: some View {
        if cachedDisplayQuestions.isEmpty {
            ContentUnavailableView(
                "选择部门",
                systemImage: "building.2",
                description: Text("从顶部选择一个部门开始调研")
            )
        } else {
            VStack(spacing: 0) {
                questionProgressBar

                ScrollView {
                    VStack(spacing: 1) {
                        let questions = cachedDisplayQuestions
                        let fi = focusedQuestionIndex
                        let count = questions.count

                        // 计算 3 卡片索引：边界自适应
                        let indices: (prev: Int?, next: Int?) = {
                            if count <= 1 { return (nil, nil) }
                            if fi == 0 { return (nil, 1) }
                            if fi >= count - 1 { return (fi - 1, nil) }
                            return (fi - 1, fi + 1)
                        }()

                        // 边界时补充额外相邻卡片（保证始终 3 张）
                        if fi == 0, count > 2 {
                            // 没有上方卡片，补一张 fi+2
                        } else if fi >= count - 1, fi - 2 >= 0 {
                            adjacentCard(question: questions[fi - 2], index: fi - 2)
                                .id("q-\(fi - 2)")
                        }

                        // 上方相邻卡片
                        if let prev = indices.prev {
                            adjacentCard(question: questions[prev], index: prev)
                                .id("q-\(prev)")
                        }

                        // 聚焦卡片
                        if fi < count {
                            let question = questions[fi]
                            if let answer = findAnswer(for: question.id, departmentId: selectedDepartmentId ?? "") {
                                let triggerResults: [TriggerEngine.TriggerResult] = {
                                    guard let triggers = question.triggers, !triggers.isEmpty, answer.hasContent else { return [] }
                                    return TriggerEngine.evaluate(triggers: triggers, answer: answer.textValue, selectedOptions: answer.selectedOptions)
                                }()
                                FocusedCardContent(
                                    question: question,
                                    index: fi,
                                    answer: answer,
                                    project: project,
                                    departments: pluginLoader.selectedDepartments(ids: project.selectedDepartmentIds),
                                    selectedDepartmentId: selectedDepartmentId ?? "",
                                    aiOptions: project.aiEnhancement?.optionSets[question.id],
                                    onIgnoreToggle: {
                                        answer.status = answer.status == .ignored ? .unanswered : .ignored
                                    },
                                    onTransfer: { deptId in
                                        answer.status = .transferred
                                        if let dept = pluginLoader.departments.first(where: { $0.id == deptId }) {
                                            answer.noteText += "\n[转移至: \(dept.name)]"
                                        }
                                    },
                                    onAnswerChanged: {
                                        scheduleFollowups(question: question, answer: answer)
                                        scheduleAIPolish(question: question, answer: answer)
                                    },
                                    onNoteChanged: {
                                        scheduleAIPolish(question: question, answer: answer)
                                    },
                                    polishStatus: polishStatus,
                                    isLLMConfigured: settings.isLLMConfigured,
                                    onManualPolish: {
                                        triggerAIPolish(question: question, answer: answer)
                                    },
                                    followups: followups,
                                    isLoadingFollowups: isLoadingFollowups,
                                    onDismissFollowups: { followups = [] },
                                    onAdoptFollowup: { idx in adoptFollowup(at: idx, parentQuestion: question) },
                                    onIgnoreFollowup: { idx in ignoreFollowup(at: idx) },
                                    triggerResults: triggerResults,
                                    parentQuestionText: parentQuestionText(for: question.id),
                                    isFollowupQuestion: cachedFollowupIds.contains(question.id)
                                )
                                .id("q-\(fi)")
                            }
                        }

                        // 下方相邻卡片
                        if let next = indices.next {
                            adjacentCard(question: questions[next], index: next)
                                .id("q-\(next)")
                        }

                        // 边界时补充额外相邻卡片（第一题时补 fi+2）
                        if fi == 0, count > 2 {
                            adjacentCard(question: questions[2], index: 2)
                                .id("q-2")
                        }
                    }
                    .padding(.vertical, 8)
                }

                // 备忘录栏
                memoBar

                // 底部导航
                questionNavigationBar
            }
        }
    }

    // MARK: - 进度条

    @ViewBuilder
    private var questionProgressBar: some View {
        let total = cachedDisplayQuestions.count
        let answered = answeredCount(for: selectedDepartmentId ?? "")
        let progress = total > 0 ? Double(answered) / Double(total) : 0

        HStack(spacing: 8) {
            ProgressView(value: progress)
                .progressViewStyle(.circular)
                .tint(progress >= 1 ? .green : .accentColor)
                .scaleEffect(0.6)
                .frame(width: 18, height: 18)

            Text("\(answered)/\(total) 已完成")
                .font(.caption)
                .foregroundStyle(.secondary)

            ProgressView(value: progress)
                .tint(progress >= 1 ? .green : .accentColor)
                .frame(maxWidth: 160)

            Spacer()

            Text("第 \(focusedQuestionIndex + 1) / \(total) 题")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.fill.quaternary, in: .capsule)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: - 相邻问题卡片

    @ViewBuilder
    private func adjacentCard(question: QuestionTemplate, index: Int) -> some View {
        let answer = findAnswer(for: question.id, departmentId: selectedDepartmentId ?? "")
        let isFollowup = cachedFollowupIds.contains(question.id)

        Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                focusedQuestionIndex = index
            }
        } label: {
            HStack(spacing: 10) {
                if isFollowup {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                }
                Text("\(index + 1)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(isFollowup ? .orange : .secondary)
                    .frame(width: 18, height: 18)
                    .background(isFollowup ? AnyShapeStyle(Color.orange.opacity(0.15)) : AnyShapeStyle(.fill.quaternary), in: .circle)

                Circle()
                    .fill(statusColor(for: answer))
                    .frame(width: 6, height: 6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(question.topic)
                        .font(.system(size: 9))
                        .foregroundStyle(Color.accentColor.opacity(0.6))
                    Text(question.question)
                        .font(.callout)
                        .lineLimit(2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let ans = answer, ans.hasContent {
                    Text(String(ans.textValue.prefix(30)) + (ans.textValue.count > 30 ? "..." : ""))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .frame(maxWidth: 150, alignment: .trailing)
                }

                Image(systemName: index < focusedQuestionIndex ? "chevron.down" : "chevron.up")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.background)
            .clipShape(.rect(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.fill.tertiary, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 1)
    }

    // MARK: - 底部导航栏

    @ViewBuilder
    private var questionNavigationBar: some View {
        HStack {
            Button {
                if focusedQuestionIndex > 0 {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        focusedQuestionIndex -= 1
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("上一题")
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.fill.quaternary, in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(focusedQuestionIndex <= 0)
            .keyboardShortcut(.upArrow, modifiers: .command)

            Spacer()

            // 快速跳转
            HStack(spacing: 4) {
                Text("跳转:")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                ForEach(Array(stride(from: 0, to: min(cachedDisplayQuestions.count, 10), by: 1)), id: \.self) { idx in
                    let answer = findAnswer(for: cachedDisplayQuestions[idx].id, departmentId: selectedDepartmentId ?? "")
                    Button {
                        withAnimation { focusedQuestionIndex = idx }
                    } label: {
                        Circle()
                            .fill(
                                idx == focusedQuestionIndex
                                    ? Color.accentColor
                                    : statusColor(for: answer)
                            )
                            .frame(width: 6, height: 6)
                    }
                    .buttonStyle(.plain)
                }
                if cachedDisplayQuestions.count > 10 {
                    Text("...")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button {
                if focusedQuestionIndex < cachedDisplayQuestions.count - 1 {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        focusedQuestionIndex += 1
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("下一题")
                    Image(systemName: "chevron.right")
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.fill.quaternary, in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(cachedDisplayQuestions.isEmpty || focusedQuestionIndex >= cachedDisplayQuestions.count - 1)
            .keyboardShortcut(.downArrow, modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: - AI 调度逻辑

    func getEnhancer() -> AISurveyEnhancer {
        if let enhancer { return enhancer }
        let newEnhancer = AISurveyEnhancer(settings: settings)
        enhancer = newEnhancer
        return newEnhancer
    }

    /// 1.5 秒防抖自动润色
    func scheduleAIPolish(question: QuestionTemplate, answer: Answer) {
        guard settings.isLLMConfigured else { return }
        let hasLiveTranscript = voiceManager.state == .recording && !voiceManager.speech.transcript.isEmpty
        guard answer.hasContent || !answer.noteText.isEmpty || !answer.voiceTranscript.isEmpty || hasLiveTranscript else { return }

        polishTask?.cancel()
        polishStatus = .idle

        polishTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            triggerAIPolish(question: question, answer: answer)
        }
    }

    /// 执行 AI 润色
    private func triggerAIPolish(question: QuestionTemplate, answer: Answer) {
        guard settings.isLLMConfigured else { return }

        polishStatus = .pending
        let enhancer = getEnhancer()
        let deptId = selectedDepartmentId ?? ""

        // 合并已保存的转写 + 实时转写
        let fullTranscript: String
        let liveTranscript = voiceManager.speech.transcript
        if !liveTranscript.isEmpty && !answer.voiceTranscript.contains(liveTranscript) {
            fullTranscript = answer.voiceTranscript.isEmpty
                ? liveTranscript
                : answer.voiceTranscript + "\n" + liveTranscript
        } else {
            fullTranscript = answer.voiceTranscript
        }

        Task {
            if let result = await enhancer.polishNote(
                project: project,
                department: deptId,
                question: question.question,
                answer: answer.textValue,
                note: answer.noteText,
                transcript: fullTranscript
            ) {
                answer.polishedText = result.polished

                // 提取的结构化数据填入备忘录
                for (key, items) in result.extracts {
                    let category: MemoCategory? = switch key {
                    case "forms": .forms
                    case "metrics": .metrics
                    case "approvals": .approvals
                    case "needs": .needs
                    default: nil
                    }
                    if let cat = category {
                        for item in items where !item.isEmpty {
                            var existing = memoItems[cat] ?? []
                            // 去重：完全相同或包含关系
                            let isDuplicate = existing.contains(where: {
                                $0.localizedCaseInsensitiveCompare(item) == .orderedSame ||
                                $0.localizedCaseInsensitiveContains(item) ||
                                item.localizedCaseInsensitiveContains($0)
                            })
                            if !isDuplicate, existing.count < 20 {
                                existing.append(item)
                                memoItems[cat] = existing
                            } else if let idx = existing.firstIndex(where: { item.localizedCaseInsensitiveContains($0) && item.count > $0.count }) {
                                // 新的更详细 → 替换旧的
                                existing[idx] = item
                                memoItems[cat] = existing
                            }
                        }
                    }
                }

                polishStatus = .ready
            } else {
                polishStatus = .error(enhancer.lastError ?? "未知错误")
            }
        }
    }

    /// 1.5 秒防抖自动追问
    func scheduleFollowups(question: QuestionTemplate, answer: Answer) {
        guard settings.isLLMConfigured else { return }
        guard answer.hasContent else {
            followups = []
            return
        }

        followupTask?.cancel()
        followupTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }

            isLoadingFollowups = true
            let enhancer = getEnhancer()
            let deptId = selectedDepartmentId ?? ""

            let results = await enhancer.generateFollowup(
                project: project,
                department: deptId,
                question: question.question,
                questionType: question.type.rawValue,
                options: question.options ?? [],
                answer: answer.textValue,
                note: answer.noteText
            )

            guard !Task.isCancelled else { return }
            isLoadingFollowups = false
            if !results.isEmpty {
                followups = results
            }
        }
    }

    // MARK: - 追问采纳 / 忽略

    private func adoptFollowup(at index: Int, parentQuestion: QuestionTemplate) {
        guard index < followups.count else { return }
        let fq = followups[index]
        let deptId = selectedDepartmentId ?? ""
        let fuId = "followup-\(UUID().uuidString)"

        let template = QuestionTemplate(
            id: fuId,
            section: parentQuestion.section,
            topic: "追问·\(parentQuestion.topic)",
            question: fq.question,
            type: fq.options.isEmpty ? .text : .singleChoice,
            options: fq.options.isEmpty ? nil : fq.options,
            required: false,
            hints: fq.reason.isEmpty ? nil : [fq.reason],
            triggers: nil,
            meceGroup: nil,
            knowledgeRef: nil,
            industrySpecific: nil,
            order: parentQuestion.order
        )

        let adopted = AdoptedFollowup(
            id: fuId,
            parentQuestionId: parentQuestion.id,
            departmentId: deptId,
            template: template
        )
        adoptedFollowups.append(adopted)

        // 为追问创建 Answer
        let answer = Answer(projectId: project.id, departmentId: deptId, questionId: fuId)
        modelContext.insert(answer)
        answerLookup["\(deptId)::\(fuId)"] = answer

        // 从当前追问列表移除
        followups.remove(at: index)

        // 重建缓存
        rebuildDisplayQuestions()

        // 跳到新插入的追问
        if let newIndex = cachedDisplayQuestions.firstIndex(where: { $0.id == fuId }) {
            withAnimation(.easeInOut(duration: 0.3)) {
                focusedQuestionIndex = newIndex
            }
        }
    }

    private func ignoreFollowup(at index: Int) {
        guard index < followups.count else { return }
        followups.remove(at: index)
    }

    // MARK: - Helpers

    private func resetAIState() {
        polishTask?.cancel()
        followupTask?.cancel()
        polishStatus = .idle
        followups = []
        isLoadingFollowups = false
        updateProjectProgress()
        if focusedQuestionIndex < cachedDisplayQuestions.count {
            let q = cachedDisplayQuestions[focusedQuestionIndex]
            if let answer = findAnswer(for: q.id, departmentId: selectedDepartmentId ?? ""),
               !answer.polishedText.isEmpty {
                polishStatus = .ready
            }
        }
    }

    private func globalQuestionIndex(for question: QuestionTemplate) -> Int {
        cachedDisplayQuestions.firstIndex(where: { $0.id == question.id }) ?? 0
    }

    func statusColor(for answer: Answer?) -> Color {
        guard let answer else { return Color.gray.opacity(0.3) }
        switch answer.status {
        case .answered: return .green
        case .ignored: return .gray
        case .transferred: return .orange
        case .skipped: return .yellow
        case .unanswered:
            return answer.hasContent ? .green : .gray.opacity(0.3)
        }
    }

    // MARK: - Answer 管理

    /// 重建答案查找字典（从 allAnswers 过滤当前项目）
    func rebuildAnswerLookup() {
        var lookup: [String: Answer] = [:]
        for answer in allAnswers where answer.projectId == project.id {
            lookup["\(answer.departmentId)::\(answer.questionId)"] = answer
        }
        answerLookup = lookup
    }

    /// 重建 cachedDisplayQuestions 和 followupIds 缓存
    func rebuildDisplayQuestions() {
        cachedFollowupIds = Set(adoptedFollowups.map(\.template.id))

        guard let deptId = selectedDepartmentId else {
            cachedDisplayQuestions = []
            return
        }

        // 使用 scope 排序的问题列表
        var base = pluginLoader.questions(for: deptId, scopes: project.surveyScopes, industry: project.industryEnum)

        // 应用 AI 跳过建议
        if let skips = project.aiEnhancement?.skipSuggestions {
            base = base.filter { !skips.contains($0.id) }
        }

        // 应用 AI 优先级排序
        if let priorities = project.aiEnhancement?.priorityAdjustments {
            base.sort { a, b in
                let pa = priorities[a.id] ?? 3
                let pb = priorities[b.id] ?? 3
                return pa < pb
            }
        }

        // 插入已采纳的追问
        let deptFollowups = adoptedFollowups.filter { $0.departmentId == deptId }
        var result: [QuestionTemplate] = []
        for q in base {
            result.append(q)
            for fu in deptFollowups where fu.parentQuestionId == q.id {
                result.append(fu.template)
            }
        }

        // 追加 AI 生成的补充问题
        if let additional = project.aiEnhancement?.additionalQuestions {
            let deptAdditional = additional.filter { $0.departmentId == deptId }
            for aq in deptAdditional {
                let template = QuestionTemplate(
                    id: aq.id,
                    section: QuestionSection(rawValue: aq.section) ?? .painpoint,
                    topic: "AI补充",
                    question: aq.text,
                    type: aq.type == "multi_choice" ? .multiChoice : .singleChoice,
                    options: aq.options,
                    required: false,
                    hints: [aq.reason],
                    triggers: nil,
                    meceGroup: nil,
                    knowledgeRef: nil,
                    industrySpecific: true,
                    order: 999
                )
                result.append(template)
                // 确保有对应的 Answer
                let key = "\(deptId)::\(aq.id)"
                if answerLookup[key] == nil {
                    let answer = Answer(projectId: project.id, departmentId: deptId, questionId: aq.id)
                    modelContext.insert(answer)
                    answerLookup[key] = answer
                }
            }
        }

        cachedDisplayQuestions = result
    }

    func answeredCount(for departmentId: String) -> Int {
        answerLookup.values.filter { $0.departmentId == departmentId && $0.hasContent }.count
    }

    func findAnswer(for questionId: String, departmentId: String) -> Answer? {
        answerLookup["\(departmentId)::\(questionId)"]
    }

    private func ensureAnswersExist() {
        for deptId in project.selectedDepartmentIds {
            // 包含行业补充问题和调研范围过滤后的完整问题列表
            let questions = pluginLoader.questions(for: deptId, scopes: project.surveyScopes, industry: project.industryEnum)
            for question in questions {
                let key = "\(deptId)::\(question.id)"
                if answerLookup[key] == nil {
                    let answer = Answer(projectId: project.id, departmentId: deptId, questionId: question.id)
                    modelContext.insert(answer)
                    answerLookup[key] = answer
                }
            }
        }
    }

    private func updateProjectProgress() {
        let total = pluginLoader.totalQuestionCount(departmentIds: project.selectedDepartmentIds, industry: project.industryEnum)
        let answered = project.selectedDepartmentIds.reduce(0) { $0 + answeredCount(for: $1) }
        project.totalQuestions = total
        project.answeredQuestions = answered
        project.progress = total > 0 ? Double(answered) / Double(total) : 0
    }
}
