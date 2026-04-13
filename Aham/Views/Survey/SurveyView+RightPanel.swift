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
                    // 录音控制区（全程持续录音模式）
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "waveform")
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)
                            Text("语音录制")
                                .font(.caption)
                                .fontWeight(.medium)
                            Spacer()
                            recordingButton
                        }

                        if voiceManager.state == .recording {
                            recordingStatus

                            // 实时转写区域
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Circle()
                                        .fill(.green)
                                        .frame(width: 5, height: 5)
                                    Text("实时转写")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    // 说话人标签
                                    if let speaker = voiceManager.currentSpeaker, speaker.isConfident {
                                        HStack(spacing: 3) {
                                            Image(systemName: speaker.voicePrint.role.icon)
                                                .font(.system(size: 8))
                                            Text(speaker.voicePrint.name)
                                                .font(.caption2)
                                                .fontWeight(.medium)
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.1), in: .capsule)
                                        .foregroundStyle(Color.accentColor)
                                    }
                                }

                                ScrollView {
                                    Text(voiceManager.speech.transcript.isEmpty ? "正在聆听..." : voiceManager.speech.transcript)
                                        .font(.caption)
                                        .foregroundStyle(voiceManager.speech.transcript.isEmpty ? .tertiary : .primary)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(maxHeight: 120)
                                .padding(6)
                                .background(.fill.quaternary, in: .rect(cornerRadius: 4))

                                // 填入当前问题按钮（核心交互）
                                if !voiceManager.speech.transcript.isEmpty && focusedQuestionIndex < cachedDisplayQuestions.count {
                                    HStack(spacing: 8) {
                                        Button {
                                            fillTranscriptToCurrentQuestion()
                                        } label: {
                                            HStack(spacing: 3) {
                                                Image(systemName: "arrow.down.doc.fill")
                                                Text("填入当前问题")
                                            }
                                            .font(.caption)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(Color.accentColor, in: .capsule)
                                            .foregroundStyle(.white)
                                        }
                                        .buttonStyle(.plain)

                                        Button {
                                            fillTranscriptToNote()
                                        } label: {
                                            HStack(spacing: 3) {
                                                Image(systemName: "note.text")
                                                Text("填入笔记")
                                            }
                                            .font(.caption2)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(.fill.quaternary, in: .capsule)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        // 录音未开始时的提示
                        if voiceManager.state == .idle {
                            Text("点击「录音」开始全程录制，实时转写会显示在此处")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        // 最后一次填入记录
                        if !lastTranscript.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("上次填入")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                    Spacer()
                                    Button {
                                        lastTranscript = ""
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 8))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                Text(lastTranscript)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(3)
                            }
                            .padding(4)
                            .background(.fill.quaternary.opacity(0.5), in: .rect(cornerRadius: 4))
                        }

                        if case .error(let msg) = voiceManager.state {
                            Label(msg, systemImage: "exclamationmark.triangle")
                                .font(.caption2)
                                .foregroundStyle(.red)
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
                            let total = pluginLoader.questions(for: dept.id).count
                            let done = answeredCount(for: dept.id)
                            let pct = total > 0 ? Double(done) / Double(total) : 0
                            let isCurrent = dept.id == selectedDepartmentId

                            HStack(spacing: 6) {
                                Text(dept.name)
                                    .font(.caption2)
                                    .fontWeight(isCurrent ? .semibold : .regular)
                                    .foregroundStyle(isCurrent ? .primary : .secondary)
                                Spacer()
                                ProgressView(value: pct)
                                    .frame(width: 40)
                                    .tint(pct >= 1 ? .green : .accentColor)
                                Text("\(done)/\(total)")
                                    .font(.system(size: 9))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28, alignment: .trailing)
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

    // MARK: - 录音按钮

    @ViewBuilder
    var recordingButton: some View {
        if voiceManager.state == .recording {
            Button {
                _ = voiceManager.stopRecording()
            } label: {
                HStack(spacing: 3) {
                    Circle()
                        .fill(.red)
                        .frame(width: 6, height: 6)
                    Text("结束录音")
                        .font(.caption2)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.red.opacity(0.1), in: .capsule)
                .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                Task {
                    do {
                        try await voiceManager.startRecording(autoTranscribe: true)
                    } catch {
                        print("Recording error: \(error)")
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "mic.fill")
                        .font(.caption2)
                    Text("录音")
                        .font(.caption2)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.1), in: .capsule)
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(voiceManager.state == .transcribing)
        }
    }

    @ViewBuilder
    var recordingStatus: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.red)
                .frame(width: 6, height: 6)
                .animation(.easeInOut(duration: 0.6).repeatForever(), value: voiceManager.state == .recording)

            Text(voiceManager.formattedDuration)
                .font(.caption2)
                .monospacedDigit()

            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 2)
                    .fill(.green.gradient)
                    .frame(width: geo.size.width * CGFloat(voiceManager.capture.currentLevel))
                    .animation(.linear(duration: 0.05), value: voiceManager.capture.currentLevel)
            }
            .frame(width: 50, height: 4)
            .background(.fill.quaternary, in: .rect(cornerRadius: 2))
        }
    }

    // MARK: - 语音填入

    /// 将当前转写文本填入当前问题的回答
    func fillTranscriptToCurrentQuestion() {
        guard focusedQuestionIndex < cachedDisplayQuestions.count else { return }
        let q = cachedDisplayQuestions[focusedQuestionIndex]
        let deptId = selectedDepartmentId ?? ""

        let transcript = voiceManager.speech.transcript
        guard !transcript.isEmpty else { return }

        if let answer = findAnswer(for: q.id, departmentId: deptId) {
            if answer.textValue.isEmpty {
                answer.textValue = transcript
                answer.source = "voice"
            } else {
                answer.textValue += "\n" + transcript
            }
            answer.voiceTranscript += (answer.voiceTranscript.isEmpty ? "" : "\n") + transcript
            if answer.status == .unanswered {
                answer.status = .answered
            }
            lastTranscript = transcript
            scheduleAIPolish(question: q, answer: answer)
            scheduleFollowups(question: q, answer: answer)
        }
    }

    /// 将当前转写文本填入当前问题的顾问笔记
    func fillTranscriptToNote() {
        guard focusedQuestionIndex < cachedDisplayQuestions.count else { return }
        let q = cachedDisplayQuestions[focusedQuestionIndex]
        let deptId = selectedDepartmentId ?? ""

        let transcript = voiceManager.speech.transcript
        guard !transcript.isEmpty else { return }

        if let answer = findAnswer(for: q.id, departmentId: deptId) {
            if answer.noteText.isEmpty {
                answer.noteText = transcript
            } else {
                answer.noteText += "\n" + transcript
            }
            answer.voiceTranscript += (answer.voiceTranscript.isEmpty ? "" : "\n") + transcript
            if answer.status == .unanswered {
                answer.status = .answered
            }
            lastTranscript = transcript
            scheduleAIPolish(question: q, answer: answer)
        }
    }
}
