import SwiftUI

// MARK: - 右侧面板

extension SurveyView {

    @ViewBuilder
    var surveyRightPanel: some View {
        VStack(spacing: 0) {
            // 面板标题
            HStack {
                Text("录音 & 智能")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // 录音控制区
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "waveform")
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)
                            Text("实时录音转写")
                                .font(.caption)
                                .fontWeight(.medium)
                            Spacer()
                            recordingButton
                        }

                        // 权限未授予提示
                        if !isRecordingAvailable && !speechService.isRecording {
                            HStack(spacing: 5) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                Text("请授予麦克风与语音识别权限，点击「录音」后按提示操作")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // 录音中：实时转写内容
                        if speechService.isRecording {
                            recordingLiveView
                        }

                        // 错误提示
                        if let err = speechService.lastError {
                            Label(err, systemImage: "exclamationmark.triangle")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }

                        // 空闲提示
                        if !speechService.isRecording {
                            Text("点击「录音」，实时转写并自动填入当前问题")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(10)
                    .background(.background, in: .rect(cornerRadius: 8))

                    // AI 提示区
                    if focusedQuestionIndex < cachedDisplayQuestions.count {
                        let question = cachedDisplayQuestions[focusedQuestionIndex]

                        if let hints = question.hints, !hints.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 4) {
                                    Image(systemName: "lightbulb.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                    Text("调研提示")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                ForEach(hints, id: \.self) { hint in
                                    HStack(alignment: .top, spacing: 4) {
                                        Text("•")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                        Text(hint)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(10)
                            .background(.background, in: .rect(cornerRadius: 8))
                        }

                        // 触发反馈
                        let answer = findAnswer(for: question.id, departmentId: selectedDepartmentId ?? "")
                        if let ans = answer, !ans.textValue.isEmpty,
                           let triggers = question.triggers, !triggers.isEmpty {
                            let results = TriggerEngine.evaluate(
                                triggers: triggers,
                                answer: ans.textValue,
                                selectedOptions: ans.selectedOptions
                            )
                            if !results.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "brain")
                                            .font(.caption2)
                                            .foregroundStyle(.purple)
                                        Text("智能分析")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                    ForEach(results) { result in
                                        HStack(alignment: .top, spacing: 4) {
                                            Image(systemName: triggerIcon(for: result.type))
                                                .font(.caption2)
                                                .foregroundStyle(triggerColor(for: result.type))
                                            Text(result.content)
                                                .font(.caption)
                                        }
                                    }
                                }
                                .padding(10)
                                .background(.background, in: .rect(cornerRadius: 8))
                            }
                        }
                    }

                    // 部门完成进度
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Image(systemName: "chart.bar.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                            Text("部门进度")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        ForEach(pluginLoader.selectedDepartments(ids: project.selectedDepartmentIds)) { dept in
                            let total = baseQuestions(for: dept.id).count
                            let done = answeredCount(for: dept.id)
                            let pct = total > 0 ? Double(done) / Double(total) : 0
                            let isCurrent = dept.id == selectedDepartmentId

                            HStack(spacing: 6) {
                                Text(dept.name)
                                    .font(.caption2)
                                    .fontWeight(isCurrent ? .semibold : .regular)
                                    .foregroundStyle(isCurrent ? .primary : .secondary)
                                    .frame(minWidth: 30)
                                ProgressView(value: pct)
                                    .tint(pct >= 1 ? .green : .accentColor)
                                Text("\(done)/\(total)")
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 32, alignment: .trailing)
                            }
                        }
                    }
                    .padding(10)
                    .background(.background, in: .rect(cornerRadius: 8))

                    Spacer()
                }
                .padding(8)
            }
            .background(.background.secondary)
        }
    }

    // MARK: - 录音中实时转写视图

    @ViewBuilder
    private var recordingLiveView: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 状态行：计时 + 电平条
            HStack(spacing: 6) {
                Circle()
                    .fill(.red)
                    .frame(width: 6, height: 6)

                Text(speechService.formattedDuration)
                    .font(.caption2)
                    .monospacedDigit()

                // 固定宽度电平条（录音时显示动态动画）
                let clamped = CGFloat(max(0.04, min(1.0, speechService.isRecording ? 0.3 : 0.04)))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.12))
                    Capsule()
                        .fill(Color.green.opacity(0.65))
                        .frame(width: 50 * clamped)
                        .animation(.easeOut(duration: 0.12), value: clamped)
                }
                .frame(width: 50, height: 6)

                Spacer()
                Text("自动填入中")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // 通道2：partial 实时预览（黑字，纯显示，不触发填入）
            if !speechService.pendingText.isEmpty {
                Text(speechService.pendingText)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.06), in: .rect(cornerRadius: 4))
            }

            // 通道1：final 已填入（触发自动填入）
            if !speechService.latestConfirmedText.isEmpty {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text(speechService.latestConfirmedText)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(3)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.06), in: .rect(cornerRadius: 4))
            }

            Text("说完每句话后 AI 自动填入当前问题")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - 录音按钮

    @ViewBuilder
    var recordingButton: some View {
        if speechService.isRecording {
            Button {
                speechService.stopRecording()
            } label: {
                Label("结束录音", systemImage: "stop.fill")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .controlSize(.small)
        } else {
            Button {
                do {
                    try speechService.startRecording()
                } catch {
                    print("Recording error: \(error)")
                }
            } label: {
                Label("录音", systemImage: "mic.fill")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!isRecordingAvailable)
        }
    }

    // MARK: - 语音自动填入

    /// 将新确认的转写片段追加到 voiceTranscript，触发 AI 润色；
    /// 选择题额外触发 voiceAutoFill 自动识别并勾选选项。
    /// 转写原文不直接写入 textValue（由用户手动填写）。
    func autoFillConfirmedSegment(_ text: String) {
        guard focusedQuestionIndex < cachedDisplayQuestions.count else { return }
        let q      = cachedDisplayQuestions[focusedQuestionIndex]
        let deptId = selectedDepartmentId ?? ""
        guard let answer = findAnswer(for: q.id, departmentId: deptId) else { return }

        // 1. 仅追加到 voiceTranscript（不污染手动答案 textValue）
        answer.voiceTranscript += (answer.voiceTranscript.isEmpty ? "" : "\n") + text

        // 2. 触发 AI 润色（综合 textValue + noteText + voiceTranscript）
        scheduleAIPolish(question: q, answer: answer)

        // 3. 选择题：触发 AI 自动识别并勾选选项
        let isChoice = q.type == .singleChoice || q.type == .multiChoice
        if isChoice, let opts = q.options, !opts.isEmpty {
            scheduleVoiceAutoFill(question: q, answer: answer)
        }
    }
}
