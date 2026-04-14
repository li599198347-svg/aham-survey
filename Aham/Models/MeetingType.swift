import Foundation

/// 会议类型 — 内置 + 用户自定义
struct MeetingType: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var sfSymbol: String
    var analysisHint: String   // 传给 LLM 的分析侧重
    var isBuiltIn: Bool

    static let builtIn: [MeetingType] = [
        MeetingType(id: "sales_weekly", name: "销售周会",
                    sfSymbol: "chart.line.uptrend.xyaxis",
                    analysisHint: "关注商机进展、拜访计划、销售指标完成情况、本周待办跟踪",
                    isBuiltIn: true),
        MeetingType(id: "project",      name: "项目会议",
                    sfSymbol: "folder.badge.gearshape",
                    analysisHint: "关注里程碑节点、风险项、任务责任人和截止日期、决议事项",
                    isBuiltIn: true),
        MeetingType(id: "survey",       name: "现场调研",
                    sfSymbol: "person.2.wave.2",
                    analysisHint: "关注客户需求挖掘、现有系统痛点、数字化目标、关键业务流程",
                    isBuiltIn: true),
        MeetingType(id: "visit",        name: "客户拜访",
                    sfSymbol: "building.2",
                    analysisHint: "关注客户反馈、商机线索、竞品信息、下一步行动计划",
                    isBuiltIn: true),
    ]
}
