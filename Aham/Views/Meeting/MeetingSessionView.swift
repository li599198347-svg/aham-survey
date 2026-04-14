import SwiftUI
import SwiftData

/// 录音中的会议界面（左：实时转写，右：分析结果）
struct MeetingSessionView: View {
    let meeting: Meeting
    @Environment(MeetingRecordEngine.self) private var engine
    @Environment(SettingsManager.self)     private var settings
    @Environment(MeetingTypeStore.self)    private var typeStore
    @Environment(\.modelContext)           private var context

    @State private var analysisTab: MeetingAnalysisPanel.AnalysisTab = .minutes
    @State private var isStoppingState = false
    @State private var stopAction: StopAction = .finish

    enum StopAction { case pause, finish }

    var body: some View {
        VStack(spacing: 0) {
            recordingToolbar
            Divider()
            HSplitView {
                MeetingTranscriptPanel(
                    liveSegments: engine.liveSegments,
                    meeting: nil,
                    priorSegments: meeting.segments.sorted { $0.startTime < $1.startTime }
                )
                .frame(minWidth: 300)
                MeetingAnalysisPanel(meeting: meeting, isRecording: true,
                                     selectedTab: $analysisTab)
                    .frame(minWidth: 280)
            }
        }
        .navigationTitle(meeting.title)
        .navigationSubtitle(engine.isRecording ? "录音中" : "")
    }

    // MARK: - Toolbar

    private var recordingToolbar: some View {
        HStack(spacing: 12) {
            // 录音指示
            HStack(spacing: 6) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .opacity(engine.isRecording ? 1 : 0.3)
                    .animation(.easeInOut(duration: 0.8).repeatForever(), value: engine.isRecording)

                Text(durationText)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                    .monospacedDigit()
            }

            // 音量条
            WaveformView(level: engine.currentLevel)
                .frame(width: 120, height: 20)

            // 当前说话人
            if !engine.currentSpeaker.isEmpty {
                Label(engine.currentSpeaker, systemImage: "waveform.badge.mic")
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
            }

            Spacer()

            // 暂停 / 结束
            if isStoppingState {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(stopAction == .finish ? "分析中…" : "保存中…")
                        .font(.callout)
                }
            } else {
                HStack(spacing: 8) {
                    Button {
                        stopAction = .pause
                        stopRecording(shouldAnalyze: false)
                    } label: {
                        Label("暂停", systemImage: "pause.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .help("暂停录音，稍后可继续本次会议")

                    Button {
                        stopAction = .finish
                        stopRecording(shouldAnalyze: true)
                    } label: {
                        Label("结束会议", systemImage: "stop.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .help("结束并生成纪要")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var durationText: String {
        let t = Int(engine.recordingDuration)
        let h = t / 3600; let m = (t % 3600) / 60; let s = t % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: - Stop

    private func stopRecording(shouldAnalyze: Bool) {
        isStoppingState = true

        // 本次录音时长偏移（续录时累加历史时长）
        let timeOffset = meeting.duration
        let (audioRelPath, segs) = engine.stop(meetingId: meeting.id)

        // 追加转写片段（时间戳加上偏移量）
        for seg in segs {
            let s = MeetingSegment(startTime: seg.startTime + timeOffset,
                                   speakerName: seg.speakerName,
                                   text: seg.text)
            meeting.segments.append(s)
            context.insert(s)
        }

        // 累加时长（不覆盖，而是累加本次录音时长）
        meeting.duration += engine.recordingDuration
        if !audioRelPath.isEmpty { meeting.audioPath = audioRelPath }

        // 更新参会人
        let newSpeakers = Set(segs.map(\.speakerName)).filter { $0 != "未知" }
        if !newSpeakers.isEmpty {
            let allSpeakers = Set(meeting.participants).union(newSpeakers)
            meeting.participants = Array(allSpeakers).sorted()
        }

        meeting.updatedAt = .now

        if shouldAnalyze {
            meeting.status = .analyzing
            Task {
                await runAnalysis()
                isStoppingState = false
            }
        } else {
            meeting.status = .paused
            isStoppingState = false
        }
    }

    private func runAnalysis() async {
        let analyzer = MeetingAnalyzer()
        let mType    = typeStore.type(for: meeting.typeId)
        let segs      = meeting.segments.sorted { $0.startTime < $1.startTime }
                                        .map { "[\($0.speakerName)] \($0.text)" }

        guard let result = await analyzer.analyze(segments: segs, meetingType: mType,
                                                  settings: settings) else {
            meeting.status = .completed; return
        }

        meeting.summary         = result.summary
        meeting.minutesMarkdown = result.minutesMarkdown
        meeting.resolutions     = result.resolutions
        if !result.participants.isEmpty { meeting.participants = result.participants }

        for t in result.todos {
            let todo = MeetingTodo(content: t.content, assignee: t.assignee,
                                   dueText: t.dueText, sourceText: t.sourceText)
            meeting.todos.append(todo)
            context.insert(todo)
        }

        meeting.status    = .completed
        meeting.updatedAt = .now
    }
}

// MARK: - 音量波形

struct WaveformView: View {
    let level: Float
    @State private var bars: [Float] = Array(repeating: 0.15, count: 20)

    var body: some View {
        HStack(spacing: 2) {
            ForEach(bars.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.opacity(0.7))
                    .frame(width: 3, height: CGFloat(bars[i]) * 20)
            }
        }
        .frame(height: 20)
        .onChange(of: level) { _, newLevel in
            withAnimation(.easeOut(duration: 0.1)) {
                bars.removeFirst()
                bars.append(max(0.1, newLevel * 0.8 + Float.random(in: 0...0.15)))
            }
        }
    }
}
