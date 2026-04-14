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
            ProjectListView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            switch appStore.activeModule {
            case .sales:
                SalesDashboardView()

            case .meeting:
                MeetingMainView()

            case .survey:
                if let projectId = appStore.selectedProjectId,
                   let project = allProjects.first(where: { $0.id == projectId }) {
                    if appStore.isSurveying {
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
                        ProjectDetailView(project: project)
                    }
                } else {
                    WelcomeView()
                }
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
}

/// 无项目选中时的欢迎页
struct WelcomeView: View {
    @Environment(AppStore.self) private var appStore

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)

            Text("Aham")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("企业数字化智能平台")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("选择左侧的调研项目开始，或创建新项目")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)

            Button {
                appStore.showNewProject = true
            } label: {
                Label("新建调研", systemImage: "plus")
            }
            .keyboardShortcut("n")
            .controlSize(.large)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


#Preview {
    ContentView()
        .environment(AppStore())
        .environment(PluginLoader())
        .environment(SettingsManager())
        .environment(VoiceManager())
        .modelContainer(for: [Project.self, Answer.self], inMemory: true)
}
