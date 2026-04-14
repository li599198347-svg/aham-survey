import SwiftUI
import SwiftData

/// 会议列表 + 新建会议入口
struct MeetingListView: View {
    @Environment(AppStore.self)          private var appStore
    @Environment(MeetingRecordEngine.self) private var engine
    @Environment(MeetingTypeStore.self)  private var typeStore
    @Environment(\.modelContext)         private var context

    @Query(sort: \Meeting.date, order: .reverse) private var meetings: [Meeting]

    @State private var showNewSheet  = false
    @State private var searchText    = ""
    @State private var filterTypeId  = "all"
    @State private var meetingToDelete: Meeting?
    @State private var showDeleteAlert = false

    var body: some View {
        @Bindable var store = appStore

        VStack(spacing: 0) {
            // 搜索 + 新建
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                TextField("搜索会议", text: $searchText)
                    .textFieldStyle(.plain)
                Spacer()
                Button {
                    showNewSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help("新建会议")
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.bar)
            Divider()

            // 类型筛选
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    typeChip("全部", id: "all")
                    ForEach(typeStore.allTypes) { t in
                        typeChip(t.name, id: t.id)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
            }
            Divider()

            // 列表
            List(selection: $store.selectedMeetingId) {
                // 录音中标记
                if engine.isRecording, let activeId = engine.activeMeetingId,
                   let active = meetings.first(where: { $0.id == activeId }) {
                    Section {
                        meetingRow(active, isActive: true)
                            .tag(active.id)
                    } header: {
                        HStack(spacing: 4) {
                            Circle().fill(.red).frame(width: 6, height: 6)
                            Text("录音中").font(.caption).foregroundStyle(.red)
                        }
                    }
                }

                Section("历史会议") {
                    if filtered.isEmpty {
                        Text("暂无会议记录").font(.callout).foregroundStyle(.tertiary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(filtered) { m in
                            meetingRow(m, isActive: false)
                                .tag(m.id)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        meetingToDelete = m
                                        showDeleteAlert = true
                                    } label: { Label("删除", systemImage: "trash") }
                                }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .sheet(isPresented: $showNewSheet) {
            MeetingNewSheet()
        }
        .alert("确认删除", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let m = meetingToDelete { deleteMeeting(m) }
            }
        } message: {
            Text("删除后无法恢复，包括录音文件和转写内容。")
        }
        .onChange(of: appStore.selectedMeetingId) { _, id in
            if id != nil { appStore.activeModule = .meeting }
        }
    }

    // MARK: - Row

    private func meetingRow(_ m: Meeting, isActive: Bool) -> some View {
        let t = typeStore.type(for: m.typeId)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(m.title, systemImage: t.sfSymbol)
                    .font(.callout).fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                if isActive {
                    Text(engine.recordingDuration > 0 ? formatDuration(engine.recordingDuration) : "")
                        .font(.caption2).monospacedDigit().foregroundStyle(.red)
                } else if m.status == .paused {
                    Label("暂停中", systemImage: "pause.circle.fill")
                        .font(.caption2).foregroundStyle(.orange)
                } else {
                    Text(m.durationLabel)
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            HStack(spacing: 6) {
                Text(dateLabel(m.date)).font(.caption2).foregroundStyle(.tertiary)
                if !m.participantsLabel.isEmpty {
                    Text("·").foregroundStyle(.quaternary)
                    Text(m.participantsLabel).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Filtered

    private var filtered: [Meeting] {
        let active = engine.activeMeetingId
        var list = meetings.filter { $0.id != active || !engine.isRecording }

        if filterTypeId != "all" { list = list.filter { $0.typeId == filterTypeId } }
        if !searchText.isEmpty {
            list = list.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.participantsLabel.localizedCaseInsensitiveContains(searchText)
            }
        }
        return list
    }

    // MARK: - Type Chip

    private func typeChip(_ name: String, id: String) -> some View {
        Button(name) { filterTypeId = id }
            .buttonStyle(PillButtonStyle(selected: filterTypeId == id))
    }

    // MARK: - Actions

    private func deleteMeeting(_ m: Meeting) {
        if appStore.selectedMeetingId == m.id { appStore.selectedMeetingId = nil }
        // 删除音频文件
        if let url = m.audioURL(baseDir: MeetingRecordEngine.meetingsBaseDir) {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        context.delete(m)
    }

    // MARK: - Helpers

    private func dateLabel(_ date: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short
        return f.string(from: date)
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let total = Int(t)
        let h = total / 3600; let m = (total % 3600) / 60; let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}

private struct PillButtonStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption).fontWeight(selected ? .medium : .regular)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(selected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
            .foregroundStyle(selected ? Color.accentColor : .secondary)
            .clipShape(Capsule())
    }
}

// MARK: - New Meeting Sheet

struct MeetingNewSheet: View {
    @Environment(AppStore.self)            private var appStore
    @Environment(MeetingRecordEngine.self) private var engine
    @Environment(MeetingTypeStore.self)    private var typeStore
    @Environment(MeetingVocabularyStore.self) private var vocabStore
    @Environment(VoicePrintStore.self)     private var vpStore
    @Environment(\.modelContext)           private var context
    @Environment(\.dismiss)               private var dismiss

    @State private var title      = ""
    @State private var selectedTypeId = "sales_weekly"
    @State private var isStarting = false
    @State private var errorMsg: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("新建会议").font(.headline)

            // 类型选择
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(typeStore.allTypes) { t in
                        typeCard(t)
                    }
                }
                .padding(.horizontal, 4)
            }

            // 标题
            Form {
                TextField("会议标题", text: $title,
                          prompt: Text(defaultTitle))
                    .textFieldStyle(.roundedBorder)
            }
            .formStyle(.grouped)
            .frame(height: 70)
            .scrollDisabled(true)

            if let err = errorMsg {
                Text(err).font(.caption).foregroundStyle(.red)
            }

            Spacer()

            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    startMeeting()
                } label: {
                    if isStarting {
                        HStack { ProgressView().controlSize(.small); Text("准备中…") }
                    } else {
                        Label("开始录音", systemImage: "record.circle")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(isStarting)
            }
        }
        .padding(24)
        .frame(width: 460, height: 360)
    }

    private func typeCard(_ t: MeetingType) -> some View {
        let selected = selectedTypeId == t.id
        return Button {
            selectedTypeId = t.id
        } label: {
            VStack(spacing: 6) {
                Image(systemName: t.sfSymbol)
                    .font(.title2)
                    .foregroundStyle(selected ? .white : .accentColor)
                Text(t.name)
                    .font(.caption).fontWeight(.medium)
                    .foregroundStyle(selected ? .white : .primary)
            }
            .frame(width: 80, height: 70)
            .background(selected ? Color.accentColor : Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var defaultTitle: String {
        let t = typeStore.type(for: selectedTypeId)
        let f = DateFormatter(); f.dateFormat = "MM-dd"
        return "\(t.name) \(f.string(from: Date()))"
    }

    private func startMeeting() {
        isStarting = true
        errorMsg   = nil
        let finalTitle = title.trimmingCharacters(in: .whitespaces).isEmpty ? defaultTitle : title

        let meeting = Meeting(title: finalTitle, typeId: selectedTypeId)
        context.insert(meeting)

        // 注入依赖
        engine.voicePrintStore = vpStore
        engine.vocabularyStore = vocabStore

        Task {
            do {
                try await engine.start(meetingId: meeting.id)
                appStore.selectedMeetingId = meeting.id
                appStore.activeModule = .meeting
                dismiss()
            } catch {
                errorMsg = error.localizedDescription
                context.delete(meeting)
                isStarting = false
            }
        }
    }
}
