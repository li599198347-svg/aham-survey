import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppStore.self) private var appStore
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.updatedAt, order: .reverse) private var allProjects: [Project]

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var store = appStore

        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Column 1: Module switcher
            ModuleSidebarView()
                .navigationSplitViewColumnWidth(min: 76, ideal: 76, max: 76)
        } detail: {
            // Column 2+: Module content
            switch appStore.activeModule {

            case .home:
                HomeView()

            case .survey:
                if appStore.isSurveying, let project = currentProject {
                    SurveyView(project: project)
                        .toolbar {
                            ToolbarItem(placement: .navigation) {
                                Button {
                                    appStore.isSurveying = false
                                } label: {
                                    Label("返回项目", systemImage: "chevron.left")
                                }
                                .help("返回项目详情 (⌘⎋)")
                            }
                        }
                } else {
                    HSplitView {
                        ProjectListView()
                            .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
                        surveyDetail
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }

            case .sales:
                SalesDashboardView()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: appStore.isSurveying) { _, surveying in
            columnVisibility = surveying ? .detailOnly : .all
        }
        .onChange(of: appStore.selectedProjectId) { oldValue, newValue in
            if oldValue != newValue {
                appStore.isSurveying = false
                if newValue != nil { appStore.activeModule = .survey }
            }
        }
        .sheet(isPresented: $store.showNewProject) {
            NewProjectView()
        }
    }

    // MARK: - Computed

    private var currentProject: Project? {
        guard let id = appStore.selectedProjectId else { return nil }
        return allProjects.first(where: { $0.id == id })
    }

    // MARK: - Survey Detail

    @ViewBuilder
    private var surveyDetail: some View {
        if let project = currentProject {
            ProjectDetailView(project: project)
        } else {
            WelcomeView()
        }
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    @Environment(AppStore.self) private var appStore

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // App icon — matches Dock icon style
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 90, height: 90)
                Image(systemName: "sparkles")
                    .font(.system(size: 46, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.bottom, 28)

            Text("企业智能调研平台")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("AI 重构业务")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.top, 10)

            Divider()
                .frame(width: 240)
                .padding(.vertical, 20)

            VStack(alignment: .leading, spacing: 10) {
                featureRow("doc.text.magnifyingglass", "结构化调研，覆盖 14 大职能部门")
                featureRow("brain.head.profile",       "AI 智能分析，自动生成洞察报告")
                featureRow("mic.circle",               "语音转写，对话内容自动填入答案")
            }

            Button {
                appStore.showNewProject = true
            } label: {
                Label("新建调研项目", systemImage: "plus")
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .padding(.top, 28)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func featureRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView()
        .environment(AppStore())
        .environment(PluginLoader())
        .environment(SettingsManager())
        .environment(SpeechRecognitionService())
        .modelContainer(for: [Project.self, Answer.self], inMemory: true)
}
