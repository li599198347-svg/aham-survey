import Foundation
import AVFoundation

/// 会议文件导出：Word (.docx via HTML)、转写稿 (.md)
final class MeetingExporter {

    // MARK: - Markdown 转写稿

    static func transcriptMarkdown(meeting: Meeting, segments: [MeetingSegment]) -> String {
        var md = "# \(meeting.title) — 转写稿\n\n"
        md += "> 日期：\(formatted(meeting.date))  时长：\(meeting.durationLabel)  参会：\(meeting.participantsLabel)\n\n"
        md += "---\n\n"

        var lastSpeaker = ""
        for seg in segments.sorted(by: { $0.startTime < $1.startTime }) {
            if seg.speakerName != lastSpeaker {
                md += "\n**[\(seg.timeLabel)] \(seg.speakerName)**\n"
                lastSpeaker = seg.speakerName
            }
            md += "\(seg.text)\n"
        }
        return md
    }

    // MARK: - 纪要 Markdown

    static func minutesMarkdown(meeting: Meeting) -> String {
        var md = "# \(meeting.title)\n\n"
        md += "> 日期：\(formatted(meeting.date))  时长：\(meeting.durationLabel)  参会：\(meeting.participantsLabel)\n\n"
        if !meeting.summary.isEmpty {
            md += "## 摘要\n\n\(meeting.summary)\n\n"
        }
        md += "---\n\n"
        md += meeting.minutesMarkdown.isEmpty ? "_等待AI分析完成_" : meeting.minutesMarkdown
        return md
    }

    // MARK: - Word 导出 (HTML)

    static func minutesHTML(meeting: Meeting) -> String {
        let body = markdownToHTML(minutesMarkdown(meeting: meeting))
        return wordHTML(title: meeting.title, body: body)
    }

    static func transcriptHTML(meeting: Meeting, segments: [MeetingSegment]) -> String {
        let body = markdownToHTML(transcriptMarkdown(meeting: meeting, segments: segments))
        return wordHTML(title: "\(meeting.title) — 转写稿", body: body)
    }

    // MARK: - 音频导出（直接复制 CAF，或转 M4A）

    static func exportAudio(from sourceURL: URL, to destURL: URL) async throws {
        // 尝试 AVAssetExportSession 转 M4A
        let asset = AVURLAsset(url: sourceURL)
        guard let session = AVAssetExportSession(asset: asset,
                                                 presetName: AVAssetExportPresetAppleM4A) else {
            // 降级：直接复制
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            return
        }
        try? FileManager.default.removeItem(at: destURL)
        try await session.export(to: destURL, as: .m4a)
    }

    // MARK: - Helpers

    private static func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }

    private static func markdownToHTML(_ md: String) -> String {
        var html = ""
        for line in md.components(separatedBy: "\n") {
            if line.hasPrefix("# ")      { html += "<h1>\(escape(String(line.dropFirst(2))))</h1>\n" }
            else if line.hasPrefix("## "){ html += "<h2>\(escape(String(line.dropFirst(3))))</h2>\n" }
            else if line.hasPrefix("### "){ html += "<h3>\(escape(String(line.dropFirst(4))))</h3>\n" }
            else if line.hasPrefix("> ") { html += "<blockquote>\(escape(String(line.dropFirst(2))))</blockquote>\n" }
            else if line.hasPrefix("- ") { html += "<li>\(escape(String(line.dropFirst(2))))</li>\n" }
            else if line == "---"        { html += "<hr/>\n" }
            else if line.isEmpty         { html += "<br/>\n" }
            else {
                var l = escape(line)
                l = l.replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "<strong>$1</strong>",
                                            options: .regularExpression)
                html += "<p>\(l)</p>\n"
            }
        }
        return html
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func wordHTML(title: String, body: String) -> String {
        """
        <!DOCTYPE html>
        <html><head>
        <meta charset="utf-8"/>
        <title>\(escape(title))</title>
        <style>
          body { font-family: "Microsoft YaHei", Arial, sans-serif; max-width:800px; margin:40px auto; line-height:1.8; }
          h1 { font-size:22px; } h2 { font-size:18px; } h3 { font-size:15px; }
          blockquote { border-left:3px solid #ccc; margin:0; padding-left:12px; color:#666; }
          hr { border:none; border-top:1px solid #ddd; }
        </style>
        </head><body>
        \(body)
        </body></html>
        """
    }
}
