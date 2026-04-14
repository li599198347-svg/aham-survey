import SwiftUI

/// 会议词库设置 — 在 SettingsView「会议」Tab 中嵌套
struct MeetingVocabSettingsView: View {
    @Environment(MeetingVocabularyStore.self) private var store
    @Environment(MeetingTypeStore.self)       private var typeStore

    @State private var newTerm      = ""
    @State private var newCategory: VocabularyCategory = .project
    @State private var showAddRow   = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("添加后转写时自动识别，提升准确度")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    withAnimation { showAddRow.toggle() }
                } label: {
                    Label("添加词条", systemImage: "plus")
                }
                .controlSize(.small)
            }

            if showAddRow {
                HStack(spacing: 8) {
                    TextField("输入词条", text: $newTerm)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                    Picker("", selection: $newCategory) {
                        ForEach(VocabularyCategory.allCases) { c in
                            Text(c.label).tag(c)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 100)
                    Button("添加") {
                        store.add(term: newTerm, category: newCategory)
                        newTerm = ""; showAddRow = false
                    }
                    .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("取消") { newTerm = ""; showAddRow = false }
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            if store.terms.isEmpty {
                Text("暂无词条")
                    .font(.callout).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                // Group by category
                ForEach(VocabularyCategory.allCases) { cat in
                    let catTerms = store.terms.filter { $0.category == cat }
                    if !catTerms.isEmpty {
                        Text(cat.label)
                            .font(.caption).fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        FlowTagsView(terms: catTerms) { id in
                            store.delete(id: id)
                        }
                    }
                }
            }
        }
    }
}

private struct FlowTagsView: View {
    let terms: [VocabularyTerm]
    let onDelete: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(terms) { term in
                HStack(spacing: 4) {
                    Text(term.term).font(.caption)
                    Button {
                        onDelete(term.id)
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.secondary.opacity(0.1))
                .clipShape(Capsule())
            }
        }
    }
}
