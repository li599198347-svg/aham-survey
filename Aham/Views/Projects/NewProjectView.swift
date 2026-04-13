import SwiftUI
import SwiftData

struct NewProjectView: View {
    @Environment(AppStore.self) private var appStore
    @Environment(PluginLoader.self) private var pluginLoader
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // 基本信息
    @State private var customerName = ""
    @State private var consultant = ""
    @State private var surveyDate = Date.now

    // 行业与范围
    @State private var selectedIndustry: Industry = .general
    @State private var selectedScopes: Set<SurveyScope> = [.fullDiag]

    // 客户属性
    @State private var orgScale: OrgScale = .unset
    @State private var staffScale: StaffScale = .unset
    @State private var revenueScale: RevenueScale = .unset
    @State private var selectedSystems: Set<ERPSystem> = []

    // 部门
    @State private var selectedDeptIds: Set<String> = SurveyScope.fullDiag.defaultDepartmentIds
    @State private var showDeptCustomize = false

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("新建调研项目")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // 表单（macOS Form 自带滚动，不需要额外 ScrollView）
            Form {
                Section("基本信息") {
                    TextField("客户名称", text: $customerName)
                    TextField("顾问姓名", text: $consultant)
                    DatePicker("调研日期", selection: $surveyDate, displayedComponents: .date)
                }

                Section("行业") {
                    Picker("客户行业", selection: $selectedIndustry) {
                        ForEach(Industry.allCases) { ind in
                            Label(ind.label, systemImage: ind.icon).tag(ind)
                        }
                    }

                    if selectedIndustry != .general {
                        Text(selectedIndustry.focusAreas.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("调研范围") {
                    scopeGrid

                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.caption2)
                        Text("已自动匹配 \(selectedDeptIds.count) 个部门")
                            .font(.caption)
                        Button(showDeptCustomize ? "收起" : "自定义") {
                            showDeptCustomize.toggle()
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    }
                    .foregroundStyle(.secondary)

                    if showDeptCustomize {
                        departmentToggles
                    }
                }

                Section("客户概况（可选）") {
                    Picker("组织形态", selection: $orgScale) {
                        ForEach(OrgScale.allCases, id: \.self) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    Picker("员工规模", selection: $staffScale) {
                        ForEach(StaffScale.allCases, id: \.self) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    Picker("年营收", selection: $revenueScale) {
                        ForEach(RevenueScale.allCases, id: \.self) { s in
                            Text(s.label).tag(s)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("现有系统")
                            .font(.callout)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                            ForEach(ERPSystem.allCases) { sys in
                                let isOn = selectedSystems.contains(sys)
                                Button {
                                    if isOn { selectedSystems.remove(sys) }
                                    else { selectedSystems.insert(sys) }
                                } label: {
                                    Text(sys.rawValue)
                                        .font(.caption)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 5)
                                        .background(isOn ? Color.accentColor.opacity(0.12) : Color.clear, in: .rect(cornerRadius: 6))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(isOn ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isOn ? 1.5 : 0.5)
                                        )
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(isOn ? .primary : .secondary)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // 底部按钮
            HStack {
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("创建项目") {
                    createProject()
                }
                .buttonStyle(.borderedProminent)
                .disabled(customerName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 520, height: 680)
        .onChange(of: selectedScopes) {
            syncDepartments()
        }
    }

    // MARK: - Scope Grid

    @ViewBuilder
    private var scopeGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()), GridItem(.flexible()),
            GridItem(.flexible()), GridItem(.flexible())
        ], spacing: 8) {
            ForEach(SurveyScope.allCases) { scope in
                let isSelected = selectedScopes.contains(scope)
                Button {
                    toggleScope(scope)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: scope.icon)
                            .font(.title3)
                        Text(scope.label)
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear, in: .rect(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isSelected ? 1.5 : 0.5)
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
    }

    // MARK: - Department Toggles

    @ViewBuilder
    private var departmentToggles: some View {
        let depts = pluginLoader.departments
        ForEach(depts) { dept in
            Toggle(isOn: Binding(
                get: { selectedDeptIds.contains(dept.id) },
                set: { isOn in
                    if isOn { selectedDeptIds.insert(dept.id) }
                    else { selectedDeptIds.remove(dept.id) }
                }
            )) {
                Label(dept.name, systemImage: dept.sfSymbol)
            }
        }
    }

    // MARK: - Helpers

    private func toggleScope(_ scope: SurveyScope) {
        if scope == .fullDiag {
            selectedScopes = [.fullDiag]
        } else {
            selectedScopes.remove(.fullDiag)
            if selectedScopes.contains(scope) {
                selectedScopes.remove(scope)
                if selectedScopes.isEmpty {
                    selectedScopes = [.fullDiag]
                }
            } else {
                selectedScopes.insert(scope)
            }
        }
    }

    private func syncDepartments() {
        selectedDeptIds = SurveyScope.mergedDepartmentIds(Array(selectedScopes))
    }

    // MARK: - Create

    private func createProject() {
        let trimmedName = customerName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        let project = Project(
            name: trimmedName,
            customerName: trimmedName,
            consultant: consultant.trimmingCharacters(in: .whitespaces),
            surveyDate: surveyDate
        )
        project.industryEnum = selectedIndustry
        project.surveyScopes = Array(selectedScopes)
        project.companyScale = orgScale.rawValue
        project.headcount = staffScale.rawValue
        project.revenue = revenueScale.rawValue
        project.existingSystems = selectedSystems.map(\.rawValue).sorted().joined(separator: "、")
        project.selectedDepartmentIds = Array(selectedDeptIds)
        project.totalQuestions = pluginLoader.totalQuestionCount(departmentIds: Array(selectedDeptIds), industry: selectedIndustry)

        modelContext.insert(project)
        try? modelContext.save()
        appStore.selectedProjectId = project.id
        dismiss()
    }
}

#Preview {
    NewProjectView()
        .environment(AppStore())
        .environment(PluginLoader())
        .environment(SettingsManager())
        .environment(VoiceManager())
        .modelContainer(for: [Project.self, Answer.self], inMemory: true)
}
