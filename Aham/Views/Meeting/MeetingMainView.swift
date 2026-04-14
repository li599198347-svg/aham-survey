import SwiftUI
import SwiftData

/// 会议模块主视图 — 左侧列表 + 右侧详情分栏
struct MeetingMainView: View {
    @Environment(AppStore.self)             private var appStore
    @Query(sort: \Meeting.date, order: .reverse) private var meetings: [Meeting]

    var body: some View {
        HSplitView {
            MeetingListView()
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 340)

            detailPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: appStore.selectedMeetingId) { _, id in
            if id != nil { appStore.activeModule = .meeting }
        }
    }

    // MARK: - Detail Panel

    @ViewBuilder
    private var detailPanel: some View {
        if let meetingId = appStore.selectedMeetingId,
           let meeting = meetings.first(where: { $0.id == meetingId }) {
            if meeting.status == .recording {
                MeetingSessionView(meeting: meeting)
            } else {
                MeetingDetailView(meeting: meeting)
            }
        } else {
            MeetingPlaceholderView()
        }
    }
}

// MARK: - Placeholder

private struct MeetingPlaceholderView: View {
    @Environment(AppStore.self) private var appStore

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.circle")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("会议录音")
                .font(.largeTitle).fontWeight(.bold)
            Text("从列表选择会议，或点击「新建会议」开始录制")
                .font(.callout).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
