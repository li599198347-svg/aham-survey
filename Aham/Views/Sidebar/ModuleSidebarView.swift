import SwiftUI

/// 最左侧模块切换栏（首页 / 调研 / 销售看板 + 设置）
struct ModuleSidebarView: View {
    @Environment(AppStore.self) private var appStore

    var body: some View {
        VStack(spacing: 0) {
            // Home button (app logo)
            Button {
                appStore.isSurveying = false
                appStore.activeModule = .home
            } label: {
                let isActive = appStore.activeModule == .home
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(isActive ? Color.accentColor : Color.accentColor.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("首页")

            Divider()

            VStack(spacing: 4) {
                moduleButton(icon: "doc.text.magnifyingglass",  module: .survey, help: "调研")
                moduleButton(icon: "chart.line.uptrend.xyaxis", module: .sales,  help: "看板")
            }
            .padding(.vertical, 8)

            Spacer()

            Divider()

            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 16))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("设置 (⌘,)")
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Module Button

    private func moduleButton(icon: String,
                              module: AppModule,
                              help: String) -> some View {
        let isActive = appStore.activeModule == module
        return Button {
            appStore.isSurveying = false
            appStore.activeModule = module
        } label: {
            Image(systemName: icon)
                .font(.system(size: 18))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isActive ? Color.accentColor.opacity(0.12) : Color.clear)
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .help(help)
    }
}
