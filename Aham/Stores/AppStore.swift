import Foundation
import SwiftUI

enum AppModule: String, CaseIterable {
    case survey  = "survey"
    case sales   = "sales"
    case meeting = "meeting"
}

/// 应用级状态管理
@Observable
final class AppStore {
    /// 当前选中的项目 ID（调研模块）
    var selectedProjectId: UUID?

    /// 当前选中的会议 ID（会议模块）
    var selectedMeetingId: UUID?

    /// 是否显示新建项目 Sheet
    var showNewProject = false

    /// 搜索文本
    var searchText = ""

    /// 是否在调研模式中
    var isSurveying = false

    /// 当前激活的功能模块
    var activeModule: AppModule = .survey
}
