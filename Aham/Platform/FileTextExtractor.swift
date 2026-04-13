import Foundation
import PDFKit

/// 共享文件文本提取工具 — 支持纯文本和 PDF
enum FileTextExtractor {
    private static let textExts: Set<String> = ["txt", "md", "markdown", "json", "csv", "log", "xml", "html"]

    /// 从文件提取文本内容，不支持的格式返回 nil
    static func extractText(from url: URL) -> String? {
        let ext = url.pathExtension.lowercased()

        if textExts.contains(ext) {
            return try? String(contentsOf: url, encoding: .utf8)
        }

        if ext == "pdf" {
            return extractPDFText(url)
        }

        return nil
    }

    private static func extractPDFText(_ url: URL) -> String? {
        guard let doc = PDFDocument(url: url) else { return nil }
        var text = ""
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i), let pageText = page.string {
                text += pageText + "\n"
            }
        }
        return text.isEmpty ? nil : text
    }
}
