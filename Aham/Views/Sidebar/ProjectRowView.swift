import SwiftUI

struct ProjectRowView: View {
    let project: Project

    var body: some View {
        HStack(spacing: 10) {
            // 左：状态图标容器
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: project.status.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(iconColor)
            }

            // 中：主标题 + 副标题
            VStack(alignment: .leading, spacing: 2) {
                Text(project.displayName)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    if !project.consultant.isEmpty {
                        Text(project.consultant)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(project.surveyDate, format: .dateTime.month().day())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // 右：进度
            if project.totalQuestions > 0 {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(project.answeredQuestions)/\(project.totalQuestions)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                    ProgressView(value: project.progress)
                        .tint(progressColor)
                        .frame(width: 44)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private var iconColor: Color {
        switch project.status {
        case .draft:      .gray
        case .inProgress: .blue
        case .completed:  .green
        case .archived:   .secondary
        }
    }

    private var progressColor: Color {
        project.progress >= 1.0 ? .green : .blue
    }
}
