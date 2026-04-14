import SwiftUI
import UniformTypeIdentifiers
import SwiftData

/// 历史会议详情（左：转写稿，右：分析结果 + 导出）
struct MeetingDetailView: View {
    @Bindable var meeting: Meeting
    @Environment(\.modelContext)            private var context
    @Environment(MeetingRecordEngine.self)  private var engine
    @Environment(VoicePrintStore.self)      private var vpStore
    @Environment(MeetingVocabularyStore.self) private var vocabStore

    @State private var analysisTab: MeetingAnalysisPanel.AnalysisTab = .minutes
    @State private var showExportMenu = false
    @State private var isContinuing = false
    @State private var continueError: String?

    var body: some View {
        VStack(spacing: 0) {
            detailToolbar
            Divider()
            HSplitView {
                MeetingTranscriptPanel(liveSegments: nil, meeting: meeting)
                    .frame(minWidth: 300)
                MeetingAnalysisPanel(meeting: meeting, isRecording: false,
                                     selectedTab: $analysisTab)
                    .frame(minWidth: 280)
            }
        }
        .navigationTitle(meeting.title)
        .navigationSubtitle("\(dateLabel)  \(meeting.durationLabel)")
    }

    // MARK: - Toolbar

    private var detailToolbar: some View {
        HStack(spacing: 12) {
            // 状态
            Label(meeting.status.label, systemImage: meeting.status.icon)
                .font(.caption)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(statusColor.opacity(0.12))
                .foregroundStyle(statusColor)
                .clipShape(Capsule())

            if !meeting.participantsLabel.isEmpty {
                Label(meeting.participantsLabel, systemImage: "person.2")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            // 续录按钮（仅暂停中）
            if meeting.status == .paused {
                Button {
                    continueRecording()
                } label: {
                    if isContinuing {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("准备中…")
                        }
                    } else {
                        Label("继续录音", systemImage: "record.circle")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(isContinuing)

                if let err = continueError {
                    Text(err).font(.caption2).foregroundStyle(.red)
                }
            }

            // 导出按钮
            Menu {
                Button {
                    exportFile(type: .minutesWord)
                } label: {
                    Label("导出纪要 (.docx)", systemImage: "doc.richtext")
                }
                Button {
                    exportFile(type: .transcriptWord)
                } label: {
                    Label("导出转写稿 (.docx)", systemImage: "doc.text")
                }
                Button {
                    exportFile(type: .transcriptMd)
                } label: {
                    Label("导出转写稿 (.md)", systemImage: "doc.plaintext")
                }
                Divider()
                Button {
                    exportFile(type: .audio)
                } label: {
                    Label("导出录音 (.m4a)", systemImage: "music.note")
                }
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .buttonStyle(.bordered)
            .disabled(meeting.status != .completed)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.bar)
    }

    private var dateLabel: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: meeting.date)
    }

    private var statusColor: Color {
        switch meeting.status {
        case .recording:    .red
        case .paused:       .orange
        case .transcribing: .yellow
        case .analyzing:    .blue
        case .completed:    .green
        }
    }

    // MARK: - Continue Recording

    private func continueRecording() {
        isContinuing   = true
        continueError  = nil
        engine.voicePrintStore = vpStore
        engine.vocabularyStore = vocabStore
        Task {
            do {
                try await engine.start(meetingId: meeting.id)
                meeting.status    = .recording
                meeting.updatedAt = .now
            } catch {
                continueError = error.localizedDescription
            }
            isContinuing = false
        }
    }

    // MARK: - Export

    enum ExportType { case minutesWord, transcriptWord, transcriptMd, audio }

    private func exportFile(type: ExportType) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true

        switch type {
        case .minutesWord:
            panel.nameFieldStringValue = "\(meeting.title)_纪要.html"
            panel.message = "导出纪要（可用 Word 打开）"
            panel.allowedContentTypes = [.html]
        case .transcriptWord:
            panel.nameFieldStringValue = "\(meeting.title)_转写稿.html"
            panel.message = "导出转写稿（可用 Word 打开）"
            panel.allowedContentTypes = [.html]
        case .transcriptMd:
            panel.nameFieldStringValue = "\(meeting.title)_转写稿.md"
            panel.message = "导出转写稿 Markdown"
            panel.allowedContentTypes = [.plainText]
        case .audio:
            panel.nameFieldStringValue = "\(meeting.title).m4a"
            panel.message = "导出录音"
        }

        panel.begin { [weak meeting] response in
            guard response == .OK, let url = panel.url, let meeting else { return }
            Task {
                switch type {
                case .minutesWord:
                    let html = MeetingExporter.minutesHTML(meeting: meeting)
                    try? html.write(to: url, atomically: true, encoding: .utf8)
                case .transcriptWord:
                    let segs = meeting.segments.sorted { $0.startTime < $1.startTime }
                    let html = MeetingExporter.transcriptHTML(meeting: meeting, segments: segs)
                    try? html.write(to: url, atomically: true, encoding: .utf8)
                case .transcriptMd:
                    let segs = meeting.segments.sorted { $0.startTime < $1.startTime }
                    let md   = MeetingExporter.transcriptMarkdown(meeting: meeting, segments: segs)
                    try? md.write(to: url, atomically: true, encoding: .utf8)
                case .audio:
                    let base = MeetingRecordEngine.meetingsBaseDir
                    if let src = meeting.audioURL(baseDir: base) {
                        try? await MeetingExporter.exportAudio(from: src, to: url)
                    }
                }
            }
        }
    }
}
