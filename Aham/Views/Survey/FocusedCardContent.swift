import SwiftUI

/// 聚焦问题卡片的内容视图
/// 使用 @Bindable 直接绑定 Answer，避免自定义 Binding 导致 TextEditor 卡顿
struct FocusedCardContent: View {
    let question: QuestionTemplate
    let index: Int
    @Bindable var answer: Answer
    let project: Project
    let departments: [DepartmentTemplate]
    let selectedDepartmentId: String
    var aiOptions: [String]? = nil  // AI 增强的动态选项集

    // AI 回调
    var onIgnoreToggle: () -> Void = {}
    var onTransfer: (String) -> Void = { _ in }
    var onAnswerChanged: () -> Void = {}
    var onNoteChanged: () -> Void = {}

    // AI 状态（从父视图传入）
    var polishStatus: PolishStatus = .idle
    var isLLMConfigured: Bool = false
    var onManualPolish: () -> Void = {}
    var followups: [AISurveyEnhancer.FollowupQuestion] = []
    var isLoadingFollowups: Bool = false
    var onDismissFollowups: () -> Void = {}
    var onAdoptFollowup: (Int) -> Void = { _ in }
    var onIgnoreFollowup: (Int) -> Void = { _ in }
    var triggerResults: [TriggerEngine.TriggerResult] = []

    // 追问关联
    var parentQuestionText: String? = nil
    var isFollowupQuestion: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 问题序号 + 头部
            headerSection

            // 问题文本
            Text(question.question)
                .font(.body)
                .fontWeight(.medium)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            // 蓝色强调线
            Rectangle()
                .fill(Color.accentColor.opacity(0.3))
                .frame(height: 1)
                .padding(.horizontal, 16)

            // 主体：左边问题输入 + 右边顾问笔记 + AI润色
            HStack(alignment: .top, spacing: 0) {
                // 左：答案输入
                VStack(alignment: .leading, spacing: 8) {
                    answerInputSection
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(.fill.tertiary)
                    .frame(width: 1)

                // 右：顾问笔记 + AI润色
                VStack(alignment: .leading, spacing: 6) {
                    // 顾问记录
                    HStack {
                        Image(systemName: "pencil.line")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                        Text("顾问记录")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    TextEditor(text: $answer.noteText)
                        .font(.callout)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 100, idealHeight: 140, maxHeight: 240)
                        .padding(6)
                        .background(Color.yellow.opacity(0.06), in: .rect(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.orange.opacity(0.15), lineWidth: 0.5)
                        )
                        .onChange(of: answer.noteText) {
                            onNoteChanged()
                        }

                    // AI 润色区域
                    aiPolishSection
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 240)
            .opacity(answer.status == .ignored ? 0.4 : 1)

            // 底部：触发提示 + AI 追问
            if !triggerResults.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(triggerResults) { result in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: triggerIcon(for: result.type))
                                .font(.caption2)
                                .foregroundStyle(triggerColor(for: result.type))
                            Text(result.content)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.03))
            }

            if !followups.isEmpty {
                followupSection
            }

            // 快捷键提示
            HStack(spacing: 8) {
                Spacer()
                Text("⌘↑↓ 切题  ·  Tab 跳记录  ·  Enter 润色")
                    .font(.system(size: 9))
            }
            .foregroundStyle(.quaternary)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .background(.background)
        .clipShape(.rect(cornerRadius: 8))
        .shadow(color: (isFollowupQuestion ? Color.orange : .accentColor).opacity(0.12), radius: 6, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke((isFollowupQuestion ? Color.orange : Color.accentColor).opacity(0.35), lineWidth: 1.5)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    // MARK: - Header

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 追问关联指示
            if isFollowupQuestion, let parent = parentQuestionText {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                    Text("追问自:")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                    Text(parent)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            HStack {
                Text("\(index + 1)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(isFollowupQuestion ? Color.orange : Color.accentColor, in: .circle)

                HStack(spacing: 6) {
                    Text(question.topic)
                        .font(.caption)
                        .foregroundStyle(isFollowupQuestion ? .orange : Color.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((isFollowupQuestion ? Color.orange : Color.accentColor).opacity(0.1), in: .capsule)
                // 通用 / 行业标签
                if question.industrySpecific == true {
                    Text(project.industryEnum.label)
                        .font(.caption2)
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1), in: .capsule)
                } else {
                    Text("通用")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.1), in: .capsule)
                }

                if question.required {
                    Text("必答")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.red, in: .capsule)
                }
                if answer.status == .ignored {
                    Text("已忽略")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.gray, in: .capsule)
                }
                if answer.status == .transferred {
                    Text("已转移")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.orange, in: .capsule)
                }
            }
            Spacer()
            actionButtons
        }
            .padding(.horizontal, 16)
            .padding(.top, isFollowupQuestion ? 4 : 12)
            .padding(.bottom, 6)
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 6) {
            Button {
                onIgnoreToggle()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: answer.status == .ignored ? "eye" : "eye.slash")
                        .font(.caption)
                    Text(answer.status == .ignored ? "恢复" : "忽略")
                        .font(.caption2)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.fill.quaternary, in: .capsule)
            }
            .buttonStyle(.plain)

            Menu {
                ForEach(departments) { dept in
                    if dept.id != selectedDepartmentId {
                        Button {
                            onTransfer(dept.id)
                        } label: {
                            Label(dept.name, systemImage: dept.sfSymbol)
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.uturn.right")
                        .font(.caption)
                    Text("转移")
                        .font(.caption2)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.fill.quaternary, in: .capsule)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    // MARK: - Answer Input

    /// 实际使用的选项：AI 动态选项 > 问题默认选项
    private var effectiveOptions: [String] {
        if let ai = aiOptions, !ai.isEmpty { return ai }
        return question.options ?? []
    }

    /// 是否为多选模式
    private var isMultiChoice: Bool {
        question.type == .multiChoice
    }

    /// "其他" 是否被选中
    private var isOtherSelected: Bool {
        answer.selectedOptions.contains("__other__")
    }

    @ViewBuilder
    private var answerInputSection: some View {
        let options = effectiveOptions

        if !options.isEmpty {
            // 统一选择题 UI
            VStack(alignment: .leading, spacing: 5) {
                ForEach(options, id: \.self) { option in
                    choiceRow(option: option)
                }

                // "其他" 选项（始终显示在最后）
                if !options.contains("其他") {
                    otherOptionRow
                }

                // "其他" 文本输入
                if isOtherSelected {
                    TextField("请补充...", text: Binding(
                        get: { answer.otherText },
                        set: { newVal in
                            answer.otherText = newVal
                            syncTextValue()
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                    .padding(.leading, 30)
                }
            }
        } else {
            // 无选项时退回文本输入
            VStack(alignment: .leading, spacing: 4) {
                Text("回答")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextEditor(text: $answer.textValue)
                    .font(.callout)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 80, maxHeight: 160)
                    .padding(6)
                    .background(.fill.quaternary, in: .rect(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.fill.tertiary, lineWidth: 0.5)
                    )
                    .onChange(of: answer.textValue) {
                        markAnswered()
                        onAnswerChanged()
                    }
            }
        }
    }

    @ViewBuilder
    private func choiceRow(option: String) -> some View {
        let isSelected = isMultiChoice
            ? answer.selectedOptions.contains(option)
            : answer.selectedOptions.first == option

        HStack(spacing: 8) {
            Image(systemName: isMultiChoice
                  ? (isSelected ? "checkmark.square.fill" : "square")
                  : (isSelected ? "largecircle.fill.circle" : "circle"))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .font(.callout)
            Text(option)
                .font(.callout)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(isSelected ? Color.accentColor.opacity(0.06) : .clear, in: .rect(cornerRadius: 4))
        .contentShape(Rectangle())
        .onTapGesture {
            selectOption(option)
        }
    }

    @ViewBuilder
    private var otherOptionRow: some View {
        HStack(spacing: 8) {
            Image(systemName: isMultiChoice
                  ? (isOtherSelected ? "checkmark.square.fill" : "square")
                  : (isOtherSelected ? "largecircle.fill.circle" : "circle"))
                .foregroundStyle(isOtherSelected ? Color.accentColor : .secondary)
                .font(.callout)
            Text("其他")
                .font(.callout)
                .foregroundStyle(isOtherSelected ? .primary : .secondary)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(isOtherSelected ? Color.accentColor.opacity(0.06) : .clear, in: .rect(cornerRadius: 4))
        .contentShape(Rectangle())
        .onTapGesture {
            selectOption("__other__")
        }
    }

    private func selectOption(_ option: String) {
        if isMultiChoice {
            if answer.selectedOptions.contains(option) {
                answer.selectedOptions.removeAll { $0 == option }
            } else {
                answer.selectedOptions.append(option)
            }
        } else {
            // 单选：如果选了"其他"，清掉之前的选项
            if option == "__other__" {
                answer.selectedOptions = ["__other__"]
            } else {
                answer.selectedOptions = [option]
                answer.otherText = ""
            }
        }
        syncTextValue()
        markAnswered()
        onAnswerChanged()
    }

    private func syncTextValue() {
        let display = answer.selectedOptions.map { opt in
            opt == "__other__" ? (answer.otherText.isEmpty ? "其他" : answer.otherText) : opt
        }
        answer.textValue = display.joined(separator: " | ")
    }

    // MARK: - AI Polish Section

    @ViewBuilder
    private var aiPolishSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "wand.and.stars")
                    .font(.caption2)
                    .foregroundStyle(.purple)
                Text("AI 润色")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()

                switch polishStatus {
                case .pending:
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("生成中...")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                    }
                case .error(let msg):
                    Text("失败: \(msg)")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                case .ready:
                    Text("已生成")
                        .font(.caption2)
                        .foregroundStyle(.green)
                case .idle:
                    if isLLMConfigured {
                        Button {
                            onManualPolish()
                        } label: {
                            Text("手动润色")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            if polishStatus == .pending {
                Text("AI 润色生成中...")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.03), in: .rect(cornerRadius: 4))
            } else if !answer.polishedText.isEmpty {
                TextEditor(text: $answer.polishedText)
                    .font(.caption)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 60, idealHeight: 80, maxHeight: 140)
                    .padding(4)
                    .background(Color.blue.opacity(0.04), in: .rect(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.purple.opacity(0.15), lineWidth: 0.5)
                    )
            } else if isLLMConfigured {
                Text("记录或转录后自动生成")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                    .padding(4)
            }
        }
    }

    // MARK: - AI Followup Section

    @ViewBuilder
    private var followupSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
                Text("AI 建议追问")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.accentColor)
                if isLoadingFollowups {
                    ProgressView()
                        .controlSize(.mini)
                }
                Spacer()
                Button {
                    onDismissFollowups()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            ForEach(Array(followups.enumerated()), id: \.offset) { idx, fq in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(idx + 1).")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fq.question)
                                .font(.caption)
                                .fontWeight(.medium)
                            if !fq.method.isEmpty {
                                Text(fq.method)
                                    .font(.system(size: 9))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.accentColor.opacity(0.08), in: .capsule)
                                    .foregroundStyle(Color.accentColor)
                            }
                            if !fq.reason.isEmpty {
                                Text(fq.reason)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                    }

                    // 采纳 / 忽略按钮
                    HStack(spacing: 8) {
                        Spacer()
                        Button {
                            onIgnoreFollowup(idx)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8))
                                Text("忽略")
                                    .font(.caption2)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.fill.quaternary, in: .capsule)
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        Button {
                            onAdoptFollowup(idx)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8))
                                Text("采纳")
                                    .font(.caption2)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentColor, in: .capsule)
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.03), in: .rect(cornerRadius: 6))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.02))
    }

    // MARK: - Helpers

    private func markAnswered() {
        if answer.hasContent && answer.status == .unanswered {
            answer.status = .answered
        } else if !answer.hasContent {
            answer.status = .unanswered
        }
    }

}
