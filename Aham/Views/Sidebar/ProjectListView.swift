import SwiftUI
import SwiftData

struct ProjectListView: View {
    @Environment(AppStore.self) private var appStore
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.updatedAt, order: .reverse) private var allProjects: [Project]

    @State private var projectToDelete: Project?
    @State private var showDeleteConfirm = false

    var body: some View {
        @Bindable var store = appStore

        List(selection: $store.selectedProjectId) {
            // 平台一级导航：现场调研
            Section {
                if !activeProjects.isEmpty {
                    ForEach(activeProjects) { project in
                        ProjectRowView(project: project)
                            .tag(project.id)
                            .contextMenu { projectContextMenu(project) }
                    }
                }

                if !draftProjects.isEmpty {
                    DisclosureGroup("草稿") {
                        ForEach(draftProjects) { project in
                            ProjectRowView(project: project)
                                .tag(project.id)
                                .contextMenu { projectContextMenu(project) }
                        }
                    }
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }

                if !completedProjects.isEmpty {
                    DisclosureGroup("已完成") {
                        ForEach(completedProjects) { project in
                            ProjectRowView(project: project)
                                .tag(project.id)
                                .contextMenu { projectContextMenu(project) }
                        }
                    }
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }

                if !archivedProjects.isEmpty {
                    DisclosureGroup("已归档") {
                        ForEach(archivedProjects) { project in
                            ProjectRowView(project: project)
                                .tag(project.id)
                                .contextMenu { projectContextMenu(project) }
                        }
                    }
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }
            } header: {
                HStack {
                    Label("现场调研", systemImage: "doc.text.magnifyingglass")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Button {
                        appStore.showNewProject = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("新建调研项目 (⌘N)")
                }
            }

            // 未来功能占位（暂时禁用）
            Section {
                Label("销售会议", systemImage: "person.2")
                    .foregroundStyle(.tertiary)
                Label("评级报告", systemImage: "chart.bar.xaxis")
                    .foregroundStyle(.tertiary)
            } header: {
                Text("更多功能")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tertiary)
            }
        }
        .searchable(text: $store.searchText, prompt: "搜索")
        .alert("确认删除", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let project = projectToDelete {
                    deleteProject(project)
                }
            }
        } message: {
            Text("确定要删除「\(projectToDelete?.displayName ?? "")」吗？此操作不可撤销。")
        }
        .navigationTitle("Aham")
        .safeAreaInset(edge: .bottom) {
            HStack {
                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("设置 (⌘,)")
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .overlay {
            if allProjects.isEmpty {
                ContentUnavailableView {
                    Label("暂无调研项目", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text("点击 + 创建你的第一个现场调研项目")
                } actions: {
                    Button("新建调研") {
                        appStore.showNewProject = true
                    }
                }
            }
        }
    }

    // MARK: - Filtered Projects

    private var filteredProjects: [Project] {
        let search = appStore.searchText.trimmingCharacters(in: .whitespaces)
        guard !search.isEmpty else { return allProjects }
        return allProjects.filter {
            $0.customerName.localizedCaseInsensitiveContains(search) ||
            $0.name.localizedCaseInsensitiveContains(search) ||
            $0.consultant.localizedCaseInsensitiveContains(search)
        }
    }

    private var activeProjects: [Project] {
        filteredProjects.filter { $0.status == .inProgress }
    }

    private var draftProjects: [Project] {
        filteredProjects.filter { $0.status == .draft }
    }

    private var completedProjects: [Project] {
        filteredProjects.filter { $0.status == .completed }
    }

    private var archivedProjects: [Project] {
        filteredProjects.filter { $0.status == .archived }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func projectContextMenu(_ project: Project) -> some View {
        if project.status == .draft {
            Button {
                project.status = .inProgress
                project.updatedAt = .now
            } label: {
                Label("开始调研", systemImage: "play")
            }
        }

        if project.status == .inProgress {
            Button {
                project.status = .completed
                project.updatedAt = .now
            } label: {
                Label("标记完成", systemImage: "checkmark.circle")
            }
        }

        if project.status != .archived {
            Button {
                project.status = .archived
                project.updatedAt = .now
            } label: {
                Label("归档", systemImage: "archivebox")
            }
        }

        if project.status == .archived {
            Button {
                project.status = .completed
                project.updatedAt = .now
            } label: {
                Label("取消归档", systemImage: "arrow.uturn.backward")
            }
        }

        Divider()

        Button {
            duplicateProject(project)
        } label: {
            Label("复制项目", systemImage: "doc.on.doc")
        }

        Divider()

        Button(role: .destructive) {
            projectToDelete = project
            showDeleteConfirm = true
        } label: {
            Label("删除", systemImage: "trash")
        }
    }

    // MARK: - Actions

    private func duplicateProject(_ project: Project) {
        let copy = Project(
            name: project.name,
            customerName: project.customerName + " (副本)",
            consultant: project.consultant,
            surveyDate: .now
        )
        copy.aiFollowup = project.aiFollowup
        copy.aiNotePolish = project.aiNotePolish
        copy.aiCoach = project.aiCoach
        copy.aiCrossDept = project.aiCrossDept
        copy.aiVoiceFill = project.aiVoiceFill
        copy.selectedDepartmentIds = project.selectedDepartmentIds
        copy.industry = project.industry
        copy.surveyScopeIds = project.surveyScopeIds
        copy.aiEnhancementData = project.aiEnhancementData
        copy.companyScale = project.companyScale
        copy.headcount = project.headcount
        copy.revenue = project.revenue
        copy.existingSystems = project.existingSystems
        copy.surveyGoal = project.surveyGoal
        copy.totalQuestions = project.totalQuestions
        modelContext.insert(copy)
        appStore.selectedProjectId = copy.id
    }

    private func deleteProject(_ project: Project) {
        if appStore.selectedProjectId == project.id {
            appStore.selectedProjectId = nil
        }
        // Delete associated answers first
        let projectId = project.id
        let descriptor = FetchDescriptor<Answer>(predicate: #Predicate { $0.projectId == projectId })
        if let answers = try? modelContext.fetch(descriptor) {
            for answer in answers {
                modelContext.delete(answer)
            }
        }
        modelContext.delete(project)
    }
}
