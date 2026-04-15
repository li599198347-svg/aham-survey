import SwiftUI

struct HomeView: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 80, height: 80)
                Image(systemName: "sparkles")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.bottom, 20)

            Text("Aham")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("知识积淀 · 创新领先 · 效率为本")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.top, 6)

            // Three keyword badges
            HStack(spacing: 16) {
                keywordBadge(icon: "brain.head.profile", label: "知识", desc: "深度行业洞察", color: .purple)
                keywordBadge(icon: "lightbulb",          label: "创新", desc: "AI 驱动突破",  color: .orange)
                keywordBadge(icon: "bolt.circle",        label: "效率", desc: "极致运营效能", color: .teal)
            }
            .padding(.top, 32)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func keywordBadge(icon: String, label: String, desc: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(label)
                .font(.callout)
                .fontWeight(.semibold)

            Text(desc)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 88)
    }
}

#Preview {
    HomeView()
        .frame(width: 600, height: 400)
}
