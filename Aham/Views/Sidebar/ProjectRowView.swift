import SwiftUI

struct ProjectRowView: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: project.status.icon)
                    .foregroundStyle(iconColor)
                    .font(.caption)
                Text(project.displayName)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                if !project.consultant.isEmpty {
                    Text(project.consultant)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(project.surveyDate, format: .dateTime.month().day())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                if project.totalQuestions > 0 {
                    Text("\(project.answeredQuestions)/\(project.totalQuestions)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if project.totalQuestions > 0 {
                ProgressView(value: project.progress)
                    .tint(progressColor)
                    .scaleEffect(y: 0.5)
            }
        }
        .padding(.vertical, 2)
    }

    private var iconColor: Color {
        switch project.status {
        case .draft: .gray
        case .inProgress: .blue
        case .completed: .green
        case .archived: .secondary
        }
    }

    private var progressColor: Color {
        project.progress >= 1.0 ? .green : .blue
    }
}
