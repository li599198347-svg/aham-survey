import Foundation

/// 使用 LLM 分析会议转写，生成纪要、待办、决议
final class MeetingAnalyzer {

    struct AnalysisResult {
        var summary: String
        var minutesMarkdown: String
        var resolutions: [String]
        var todos: [TodoItem]
        var participants: [String]

        struct TodoItem {
            var content: String
            var assignee: String
            var dueText: String
            var sourceText: String
        }
    }

    func analyze(
        segments: [String],          // ["[张三] 这个项目...", ...]
        meetingType: MeetingType,
        settings: SettingsManager
    ) async -> AnalysisResult? {
        guard let provider = settings.llmProvider else { return nil }
        let transcript = segments.joined(separator: "\n")
        guard !transcript.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }

        let systemPrompt = """
你是专业会议助手，擅长分析会议记录并生成结构化输出。
会议类型：\(meetingType.name)
分析侧重：\(meetingType.analysisHint)
请用中文回答。
"""

        let userPrompt = """
以下是会议转写记录，请分析并严格按JSON格式输出：

\(transcript)

输出JSON格式（不要有任何说明文字，只输出JSON）：
{
  "summary": "100字内摘要",
  "participants": ["参会人1", "参会人2"],
  "resolutions": ["决议1", "决议2"],
  "todos": [
    {"content": "具体任务", "assignee": "责任人", "dueText": "截止时间描述", "sourceText": "原文片段"}
  ],
  "minutes": "完整Markdown纪要（含二级标题、议题、讨论要点、决议）"
}
"""

        let messages: [LLMMessage] = [
            LLMMessage(role: .system, content: systemPrompt),
            LLMMessage(role: .user,   content: userPrompt)
        ]

        let options = LLMOptions(maxTokens: 4000, temperature: 0.3, timeout: 120)
        guard let fullText = try? await provider.chat(messages: messages, options: options) else {
            return nil
        }

        return parseJSON(fullText)
    }

    // MARK: - JSON Parsing

    private func parseJSON(_ raw: String) -> AnalysisResult? {
        // Extract JSON block
        var jsonStr = raw
        if let start = raw.range(of: "{"), let end = raw.range(of: "}", options: .backwards) {
            jsonStr = String(raw[start.lowerBound...end.lowerBound])
        }

        guard let data = jsonStr.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Fallback: treat whole response as minutes
            return AnalysisResult(summary: "", minutesMarkdown: raw,
                                  resolutions: [], todos: [], participants: [])
        }

        let summary     = obj["summary"]      as? String ?? ""
        let minutes     = obj["minutes"]      as? String ?? ""
        let resolutions = obj["resolutions"]  as? [String] ?? []
        let participants = obj["participants"] as? [String] ?? []

        var todos: [AnalysisResult.TodoItem] = []
        if let rawTodos = obj["todos"] as? [[String: Any]] {
            for t in rawTodos {
                todos.append(AnalysisResult.TodoItem(
                    content:    t["content"]    as? String ?? "",
                    assignee:   t["assignee"]   as? String ?? "",
                    dueText:    t["dueText"]    as? String ?? "",
                    sourceText: t["sourceText"] as? String ?? ""
                ))
            }
        }

        return AnalysisResult(summary: summary, minutesMarkdown: minutes,
                              resolutions: resolutions, todos: todos, participants: participants)
    }
}
