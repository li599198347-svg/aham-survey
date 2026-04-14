import SwiftUI
import SwiftData

@main
struct AhamApp: App {
    @State private var appStore        = AppStore()
    @State private var pluginLoader    = PluginLoader()
    @State private var settingsManager = SettingsManager()
    @State private var voiceManager    = VoiceManager()
    @State private var voicePrintStore = VoicePrintStore()
    @State private var meetingEngine   = MeetingRecordEngine()
    @State private var meetingTypeStore    = MeetingTypeStore()
    @State private var meetingVocabStore   = MeetingVocabularyStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appStore)
                .environment(pluginLoader)
                .environment(settingsManager)
                .environment(voiceManager)
                .environment(voicePrintStore)
                .environment(meetingEngine)
                .environment(meetingTypeStore)
                .environment(meetingVocabStore)
                .onAppear {
                    voiceManager.voicePrintStore = voicePrintStore
                    meetingEngine.voicePrintStore = voicePrintStore
                    meetingEngine.vocabularyStore = meetingVocabStore
                }
        }
        .modelContainer(for: [Project.self, Answer.self, Meeting.self,
                               MeetingSegment.self, MeetingTodo.self])
        .defaultSize(width: 1200, height: 800)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建项目") {
                    appStore.showNewProject = true
                }
                .keyboardShortcut("n")
            }

            CommandGroup(after: .newItem) {
                Divider()

                Button("开始/继续调研") {
                    appStore.isSurveying = true
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(appStore.selectedProjectId == nil)

                Button("返回项目") {
                    appStore.isSurveying = false
                }
                .keyboardShortcut(.escape, modifiers: .command)
                .disabled(!appStore.isSurveying)
            }
        }

        Settings {
            SettingsView()
                .environment(settingsManager)
                .environment(pluginLoader)
                .environment(voicePrintStore)
                .environment(voiceManager)
                .environment(meetingTypeStore)
                .environment(meetingVocabStore)
        }
    }
}
