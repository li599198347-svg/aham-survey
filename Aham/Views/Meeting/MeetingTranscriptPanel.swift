import SwiftUI
import SwiftData

/// 左栏：实时转写（录音中）或历史转写（带播放定位）
struct MeetingTranscriptPanel: View {
    // 录音中：传 liveSegments；已完成：传 nil，从 meeting.segments 读
    let liveSegments: [MeetingRecordEngine.LiveSegment]?
    let meeting: Meeting?
    /// 续录时传入已保存的历史片段（在 live 面板上方展示）
    var priorSegments: [MeetingSegment] = []

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let live = liveSegments {
                        // 续录：先展示历史片段
                        if !priorSegments.isEmpty {
                            priorView(priorSegments)
                            HStack {
                                Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1)
                                Text("本次录音").font(.caption2).foregroundStyle(.tertiary)
                                    .fixedSize()
                                Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 10)
                        }
                        liveView(live, proxy: proxy)
                    } else if let m = meeting {
                        historyView(m)
                    }
                }
                .padding(16)
            }
            .onChange(of: liveSegments?.count) { _, _ in
                if let last = liveSegments?.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    // MARK: - Prior (续录历史)

    @ViewBuilder
    private func priorView(_ segs: [MeetingSegment]) -> some View {
        ForEach(segs) { seg in
            segmentBubble(time: seg.timeLabel, speaker: seg.speakerName,
                          text: seg.text, pending: false)
        }
    }

    // MARK: - Live

    @ViewBuilder
    private func liveView(_ segs: [MeetingRecordEngine.LiveSegment],
                          proxy: ScrollViewProxy) -> some View {
        if segs.isEmpty {
            emptyHint("等待说话…")
        } else {
            ForEach(segs) { seg in
                segmentBubble(
                    time:    timeLabel(seg.startTime),
                    speaker: seg.speakerName,
                    text:    seg.text,
                    pending: !seg.isFinal
                )
                .id(seg.id)
            }
        }
    }

    // MARK: - History

    @ViewBuilder
    private func historyView(_ m: Meeting) -> some View {
        let sorted = m.segments.sorted { $0.startTime < $1.startTime }
        if sorted.isEmpty {
            emptyHint("暂无转写内容")
        } else {
            ForEach(sorted) { seg in
                segmentBubble(time: seg.timeLabel, speaker: seg.speakerName,
                              text: seg.text, pending: false)
            }
        }
    }

    // MARK: - Bubble

    @ViewBuilder
    private func segmentBubble(time: String, speaker: String, text: String, pending: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(time)
                    .font(.caption2).monospacedDigit()
                    .foregroundStyle(.tertiary)
                Text(speaker)
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                if pending {
                    ProgressView().controlSize(.mini).scaleEffect(0.7)
                }
            }
            Text(text)
                .font(.callout)
                .foregroundStyle(pending ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 2)
        Divider().opacity(0.4)
    }

    private func emptyHint(_ msg: String) -> some View {
        Text(msg)
            .font(.callout).foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.top, 60)
    }

    private func timeLabel(_ t: TimeInterval) -> String {
        let m = Int(t) / 60; let s = Int(t) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
