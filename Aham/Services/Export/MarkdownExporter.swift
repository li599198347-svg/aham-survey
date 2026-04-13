import Foundation

/// Markdown 导出引擎 — 将项目调研数据生成结构化 Markdown
struct MarkdownExporter {

    /// 生成完整的项目调研报告 Markdown
    static func exportProject(
        project: Project,
        answers: [Answer],
        pluginLoader: PluginLoader,
        config: ExportConfig = .default
    ) -> String {
        var md = ""

        // Frontmatter
        if config.addFrontmatter {
            md += frontmatter(project: project)
        }

        // 标题
        md += "# \(project.displayName) — 调研报告\n\n"

        // 项目概况
        md += projectOverview(project: project, config: config)

        // 各部门调研内容
        for deptId in project.selectedDepartmentIds {
            let deptAnswers = answers.filter { $0.departmentId == deptId }
            let dept = pluginLoader.departments.first { $0.id == deptId }
            let deptName = dept?.name ?? deptId

            md += "\n---\n\n"
            md += "## \(deptName)\n\n"

            let sections = pluginLoader.questionsBySection(for: deptId)
            for (section, questions) in sections {
                let sectionAnswers = questions.compactMap { q in
                    deptAnswers.first { $0.questionId == q.id }.map { (q, $0) }
                }.filter { $0.1.hasContent }

                if sectionAnswers.isEmpty { continue }

                md += "### \(section.label)\n\n"

                for (question, answer) in sectionAnswers {
                    md += questionBlock(
                        question: question,
                        answer: answer,
                        config: config
                    )
                }
            }
        }

        // 进度摘要
        md += "\n---\n\n"
        md += "## 调研统计\n\n"
        md += "- 总问题数: \(project.totalQuestions)\n"
        md += "- 已回答: \(project.answeredQuestions)\n"
        md += "- 完成率: \(Int(project.progress * 100))%\n"
        md += "- 调研部门: \(project.selectedDepartmentIds.count) 个\n"
        md += "- 导出时间: \(Date.now.formatted(.dateTime.year().month().day().hour().minute()))\n"

        return md
    }

    /// 导出单个部门
    static func exportDepartment(
        project: Project,
        departmentId: String,
        answers: [Answer],
        pluginLoader: PluginLoader,
        config: ExportConfig = .default
    ) -> String {
        let dept = pluginLoader.departments.first { $0.id == departmentId }
        let deptName = dept?.name ?? departmentId
        let deptAnswers = answers.filter { $0.departmentId == departmentId }

        var md = ""

        if config.addFrontmatter {
            md += "---\n"
            md += "project: \"\(yamlEscape(project.displayName))\"\n"
            md += "department: \"\(yamlEscape(deptName))\"\n"
            md += "date: \(project.surveyDate.formatted(.iso8601.year().month().day()))\n"
            md += "---\n\n"
        }

        md += "# \(deptName) — \(project.displayName)\n\n"

        let sections = pluginLoader.questionsBySection(for: departmentId)
        for (section, questions) in sections {
            let sectionAnswers = questions.compactMap { q in
                deptAnswers.first { $0.questionId == q.id }.map { (q, $0) }
            }.filter { $0.1.hasContent }

            if sectionAnswers.isEmpty { continue }

            md += "## \(section.label)\n\n"

            for (question, answer) in sectionAnswers {
                md += questionBlock(question: question, answer: answer, config: config)
            }
        }

        return md
    }

    // MARK: - Private

    private static func frontmatter(project: Project) -> String {
        var yaml: [String] = ["---"]
        yaml.append("title: \"\(yamlEscape(project.displayName + " 调研报告"))\"")
        yaml.append("customer: \"\(yamlEscape(project.customerName))\"")
        if !project.consultant.isEmpty {
            yaml.append("consultant: \"\(yamlEscape(project.consultant))\"")
        }
        yaml.append("date: \(project.surveyDate.formatted(.iso8601.year().month().day()))")
        yaml.append("status: \(project.status.label)")
        yaml.append("industry: \(project.industryEnum.label)")
        yaml.append("progress: \(Int(project.progress * 100))%")
        yaml.append("tags:")
        yaml.append("  - 调研报告")
        yaml.append("  - \"\(yamlEscape(project.customerName))\"")
        yaml.append("---\n\n")
        return yaml.joined(separator: "\n")
    }

    private static func yamlEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
             .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func projectOverview(project: Project, config: ExportConfig) -> String {
        var md = "## 项目概况\n\n"
        md += "| 项目 | 信息 |\n|------|------|\n"
        md += "| 客户 | \(project.customerName) |\n"
        if !project.consultant.isEmpty {
            md += "| 顾问 | \(project.consultant) |\n"
        }
        md += "| 调研日期 | \(project.surveyDate.formatted(.dateTime.year().month().day())) |\n"
        md += "| 状态 | \(project.status.label) |\n"
        if !project.companyScale.isEmpty {
            md += "| 企业规模 | \(project.companyScale) |\n"
        }
        if !project.headcount.isEmpty {
            md += "| 人数 | \(project.headcount) |\n"
        }
        if !project.revenue.isEmpty {
            md += "| 营收 | \(project.revenue) |\n"
        }
        if !project.existingSystems.isEmpty {
            md += "| 已有系统 | \(project.existingSystems) |\n"
        }
        md += "\n"

        if !project.surveyGoal.isEmpty {
            md += "> **调研目标**: \(project.surveyGoal)\n\n"
        }

        return md
    }

    private static func questionBlock(
        question: QuestionTemplate,
        answer: Answer,
        config: ExportConfig
    ) -> String {
        var md = ""

        // 问题
        md += "**\(question.topic)** — \(question.question)\n\n"

        // 回答
        if !answer.selectedOptions.isEmpty && answer.selectedOptions != [answer.textValue] {
            for opt in answer.selectedOptions {
                md += "- [x] \(opt)\n"
            }
            md += "\n"
        } else if !answer.textValue.isEmpty {
            md += "> \(answer.textValue.replacingOccurrences(of: "\n", with: "\n> "))\n\n"
        }

        // AI 润色
        if config.includeAIPolish && !answer.polishedText.isEmpty {
            md += "*AI 润色:* \(answer.polishedText)\n\n"
        }

        // 顾问笔记
        if config.includeNotes && !answer.noteText.isEmpty {
            md += "*笔记:* \(answer.noteText)\n\n"
        }

        // 语音转写
        if config.includeVoice && !answer.voiceTranscript.isEmpty {
            md += "*语音记录:* \(answer.voiceTranscript)\n\n"
        }

        return md
    }
}

/// 导出配置
struct ExportConfig {
    var addFrontmatter: Bool
    var includeNotes: Bool
    var includeAIPolish: Bool
    var includeVoice: Bool
    var useWikiLinks: Bool

    static let `default` = ExportConfig(
        addFrontmatter: true,
        includeNotes: true,
        includeAIPolish: true,
        includeVoice: true,
        useWikiLinks: true
    )
}
