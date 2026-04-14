import SwiftUI
import SwiftData

/// 右栏：会议分析（纪要 / 待办 / 发言统计）
struct MeetingAnalysisPanel: View {
    let meeting: Meeting
    let isRecording: Bool      // 录音中时显示等待占位
    @Binding var selectedTab: AnalysisTab

    enum AnalysisTab: String, CaseIterable {
        case minutes = "纪要"
        case todos   = "待办"
        case stats   = "统计"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(AnalysisTab.allCases, id: \.self) { tab in
                    Button(tab.rawValue) { selectedTab = tab }
                        .buttonStyle(AnalysisTabStyle(selected: selectedTab == tab))
                }
                Spacer()
            }
            .background(Color.secondary.opacity(0.06))
            Divider()

            // Content
            ScrollView {
                Group {
                    switch selectedTab {
                    case .minutes: minutesContent
                    case .todos:   todosContent
                    case .stats:   statsContent
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - 纪要

    @ViewBuilder
    private var minutesContent: some View {
        if isRecording {
            pendingHint("录音结束后自动生成纪要…")
        } else if meeting.status == .analyzing {
            analyzingView
        } else if meeting.minutesMarkdown.isEmpty {
            pendingHint("暂无纪要")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if !meeting.summary.isEmpty {
                    GroupBox("摘要") {
                        Text(meeting.summary)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if !meeting.resolutions.isEmpty {
                    GroupBox("决议事项") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(meeting.resolutions, id: \.self) { r in
                                Label(r, systemImage: "checkmark.seal.fill")
                                    .font(.callout)
                                    .foregroundStyle(.primary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                GroupBox("会议纪要") {
                    Text(meeting.minutesMarkdown)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - 待办

    @ViewBuilder
    private var todosContent: some View {
        if isRecording {
            pendingHint("录音结束后自动提取待办…")
        } else if meeting.todos.isEmpty {
            pendingHint("暂无待办事项")
        } else {
            VStack(spacing: 8) {
                ForEach(meeting.todos.sorted { !$0.isDone && $1.isDone }) { todo in
                    TodoRow(todo: todo)
                }
            }
        }
    }

    // MARK: - 统计

    @ViewBuilder
    private var statsContent: some View {
        let segments = meeting.segments
        if segments.isEmpty {
            pendingHint("暂无统计数据")
        } else {
            let speakers = speakerStats(segments: segments)
            VStack(alignment: .leading, spacing: 12) {
                GroupBox("发言统计") {
                    VStack(spacing: 10) {
                        ForEach(speakers, id: \.name) { s in
                            speakerRow(s)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
                GroupBox("基本信息") {
                    VStack(alignment: .leading, spacing: 6) {
                        infoRow("时长", meeting.durationLabel)
                        infoRow("段落", "\(segments.count) 段")
                        infoRow("参会", meeting.participantsLabel.isEmpty ? "—" : meeting.participantsLabel)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Speaker Stats

    struct SpeakerStat {
        var name: String; var count: Int; var ratio: Double
    }

    private func speakerStats(segments: [MeetingSegment]) -> [SpeakerStat] {
        var counts: [String: Int] = [:]
        for seg in segments { counts[seg.speakerName, default: 0] += 1 }
        let total = segments.count
        return counts
            .map { SpeakerStat(name: $0.key, count: $0.value, ratio: Double($0.value) / Double(total)) }
            .sorted { $0.count > $1.count }
    }

    private func speakerRow(_ s: SpeakerStat) -> some View {
        HStack(spacing: 10) {
            Text(s.name).font(.callout).frame(width: 70, alignment: .leading)
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.accentColor.opacity(0.3))
                    .frame(width: geo.size.width * s.ratio)
            }
            .frame(height: 12)
            Text(String(format: "%.0f%%", s.ratio * 100))
                .font(.caption).foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
        }
        .frame(height: 20)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.callout).foregroundStyle(.secondary).frame(width: 50, alignment: .leading)
            Text(value).font(.callout)
        }
    }

    // MARK: - Helpers

    private var analyzingView: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            Text("AI 分析中…").font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }

    private func pendingHint(_ msg: String) -> some View {
        Text(msg).font(.callout).foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 60)
    }
}

// MARK: - TodoRow

private struct TodoRow: View {
    @Bindable var todo: MeetingTodo

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                withAnimation { todo.isDone.toggle() }
            } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(todo.isDone ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(todo.content)
                    .font(.callout)
                    .strikethrough(todo.isDone)
                    .foregroundStyle(todo.isDone ? .secondary : .primary)
                HStack(spacing: 8) {
                    if !todo.assignee.isEmpty {
                        Label(todo.assignee, systemImage: "person")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if !todo.dueText.isEmpty {
                        Label(todo.dueText, systemImage: "calendar")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Tab Style

private struct AnalysisTabStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline).fontWeight(selected ? .semibold : .regular)
            .foregroundStyle(selected ? .primary : .secondary)
            .padding(.horizontal, 16).frame(height: 36)
            .overlay(alignment: .bottom) {
                if selected { Rectangle().fill(Color.accentColor).frame(height: 2) }
            }
    }
}
