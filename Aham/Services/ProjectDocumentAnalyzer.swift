import Foundation

/// 项目文档分析器 — 项目级，分析客户提供的文档并提取信息
@Observable
@MainActor
final class ProjectDocumentAnalyzer {
    private(set) var isAnalyzing = false
    var lastError: String?

    struct DocumentAnalysisResult {
        let companyProfile: CompanyProfile
        let knownIssues: [String]
        let knownNeeds: [String]
        let keyFindings: [String]
    }

    struct CompanyProfile {
        let industry: String
        let scale: String
        let products: String
        let systems: [String]
        let certifications: [String]
    }

    /// 分析文档并返回结构化结果
    func analyze(fileURL: URL, settings: SettingsManager) async -> DocumentAnalysisResult? {
        guard let provider = settings.llmProvider else {
            lastError = "请先在设置中配置 AI 服务"
            return nil
        }

        guard let content = readFileContent(fileURL) else {
            lastError = "无法读取文件内容"
            return nil
        }

        isAnalyzing = true
        lastError = nil
        defer { isAnalyzing = false }

        let messages = PromptTemplates.documentAnalysis(docContent: content)

        do {
            let response = try await provider.chat(messages: messages, options: .polishing)
            guard let json = LLMJSONParser.parse(response) as? [String: Any] else { return nil }

            let profileDict = json["companyProfile"] as? [String: Any] ?? [:]
            let profile = CompanyProfile(
                industry: profileDict["industry"] as? String ?? "",
                scale: profileDict["scale"] as? String ?? "",
                products: profileDict["products"] as? String ?? "",
                systems: profileDict["systems"] as? [String] ?? [],
                certifications: profileDict["certifications"] as? [String] ?? []
            )

            return DocumentAnalysisResult(
                companyProfile: profile,
                knownIssues: json["knownIssues"] as? [String] ?? [],
                knownNeeds: json["knownNeeds"] as? [String] ?? [],
                keyFindings: json["keyFindings"] as? [String] ?? []
            )
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    /// 将分析结果写入项目
    func applyToProject(_ result: DocumentAnalysisResult, project: Project) {
        let p = result.companyProfile
        if project.companyScale.isEmpty && !p.scale.isEmpty {
            project.companyScale = p.scale
        }
        if project.existingSystems.isEmpty && !p.systems.isEmpty {
            project.existingSystems = p.systems.joined(separator: "、")
        }

        // 保存文档上下文供 AI 增强使用
        var parts: [String] = []
        if !p.industry.isEmpty { parts.append("行业：\(p.industry)") }
        if !p.products.isEmpty { parts.append("产品：\(p.products)") }
        if !p.certifications.isEmpty { parts.append("认证：\(p.certifications.joined(separator: "、"))") }
        if !result.knownIssues.isEmpty { parts.append("已知问题：\(result.knownIssues.joined(separator: "；"))") }
        if !result.knownNeeds.isEmpty { parts.append("已知需求：\(result.knownNeeds.joined(separator: "；"))") }
        if !result.keyFindings.isEmpty { parts.append("关键发现：\(result.keyFindings.joined(separator: "；"))") }

        if !parts.isEmpty {
            var enhancement = project.aiEnhancement ?? AIProjectEnhancement()
            enhancement.documentContext = parts.joined(separator: "\n")
            project.aiEnhancement = enhancement
        }

        project.updatedAt = .now
    }

    // MARK: - 文件读取

    private func readFileContent(_ url: URL) -> String? {
        FileTextExtractor.extractText(from: url)
    }
}
