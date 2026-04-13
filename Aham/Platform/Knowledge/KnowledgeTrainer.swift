import Foundation

/// 知识库训练服务 — 增量提取、合并、去重
@Observable
@MainActor
final class KnowledgeTrainer {
    let store = KnowledgeStore()

    private(set) var isTraining = false
    private(set) var progress: TrainingProgress?
    private(set) var lastError: String?

    struct TrainingProgress {
        var totalFiles: Int
        var processedFiles: Int
        var skippedFiles: Int
        var newEntries: Int
        var updatedEntries: Int
        var currentFile: String
    }

    /// 开始训练：扫描文件列表，增量提取知识
    func train(fileURLs: [URL], settings: SettingsManager) async {
        guard let provider = settings.llmProvider else {
            lastError = "请先在设置中配置 AI 服务"
            return
        }

        isTraining = true
        lastError = nil
        var manifest = store.loadManifest()
        var entries = store.loadEntries()

        var prog = TrainingProgress(
            totalFiles: fileURLs.count,
            processedFiles: 0,
            skippedFiles: 0,
            newEntries: 0,
            updatedEntries: 0,
            currentFile: ""
        )
        progress = prog

        for url in fileURLs {
            prog.currentFile = url.lastPathComponent
            progress = prog

            // 计算文件 hash，检查是否已训练
            guard let hash = KnowledgeStore.fileHash(url) else {
                prog.skippedFiles += 1
                prog.processedFiles += 1
                progress = prog
                continue
            }

            if store.isFileProcessed(hash, manifest: manifest) {
                prog.skippedFiles += 1
                prog.processedFiles += 1
                progress = prog
                continue
            }

            // 读取文件内容
            guard let content = readFileContent(url) else {
                prog.skippedFiles += 1
                prog.processedFiles += 1
                progress = prog
                continue
            }

            // AI 提取知识
            let extracted = await extractKnowledge(from: content, fileName: url.lastPathComponent, provider: provider)

            // 增量合并
            let (newCount, updateCount) = mergeEntries(extracted: extracted, into: &entries)
            prog.newEntries += newCount
            prog.updatedEntries += updateCount

            // 记录已处理文件
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            let processed = ProcessedFile(
                id: hash,
                fileName: url.lastPathComponent,
                fileSize: fileSize,
                processedAt: .now,
                entriesExtracted: extracted.count
            )
            manifest.processedFiles.append(processed)

            prog.processedFiles += 1
            progress = prog
        }

        // 保存新版本
        manifest.version += 1
        manifest.lastTrainedAt = .now
        manifest.totalEntries = entries.count

        do {
            try store.save(manifest: manifest, entries: entries)
        } catch {
            lastError = "保存知识库失败: \(error.localizedDescription)"
        }

        isTraining = false
    }

    // MARK: - AI 知识提取

    private func extractKnowledge(from content: String, fileName: String, provider: any LLMProvider) async -> [KnowledgeEntry] {
        let messages = knowledgeExtractionPrompt(content: String(content.prefix(12000)))

        do {
            let response = try await provider.chat(messages: messages, options: .polishing)
            guard let json = LLMJSONParser.parse(response) as? [String: Any],
                  let items = json["entries"] as? [[String: Any]] else {
                return []
            }

            return items.compactMap { item -> KnowledgeEntry? in
                guard let cat = item["category"] as? String,
                      let content = item["content"] as? String,
                      !content.isEmpty else { return nil }

                return KnowledgeEntry(
                    id: UUID().uuidString,
                    category: KnowledgeCategory(rawValue: cat) ?? .other,
                    content: content,
                    source: fileName,
                    confidence: item["confidence"] as? Double ?? 0.7,
                    tags: item["tags"] as? [String] ?? [],
                    createdAt: .now,
                    updatedAt: .now
                )
            }
        } catch {
            lastError = "AI 提取失败: \(error.localizedDescription)"
            return []
        }
    }

    private func knowledgeExtractionPrompt(content: String) -> [LLMMessage] {
        let system = """
        你是行业知识提取专家。从文档中提取结构化的行业知识条目。

        知识类别：
        - industry_term: 行业术语和定义
        - best_practice: 最佳实践和经验
        - pain_point: 常见痛点和挑战
        - solution: 解决方案和建议
        - cross_dept: 跨部门协作关联
        - standard: 体系标准和合规要求
        - metric: 关键指标和KPI
        - other: 其他有价值的知识

        提取规则：
        - 每条知识应独立、完整、有价值
        - content 要简洁精炼（50-200字）
        - confidence: 0.9(明确陈述) / 0.7(可推断) / 0.5(模糊)
        - tags 标注关联的部门或主题

        输出 JSON：
        {
          "entries": [
            {"category": "类别", "content": "知识内容", "confidence": 0.9, "tags": ["标签"]}
          ]
        }
        """

        let user = "请从以下文档中提取行业知识：\n\n\(content)"

        return [
            LLMMessage(role: .system, content: system),
            LLMMessage(role: .user, content: user)
        ]
    }

    // MARK: - 增量合并

    /// 合并新提取的条目到已有知识库，返回 (新增数, 更新数)
    private func mergeEntries(extracted: [KnowledgeEntry], into existing: inout [KnowledgeEntry]) -> (Int, Int) {
        var newCount = 0
        var updateCount = 0

        for entry in extracted {
            // 查找是否有相似的已有条目（基于内容相似度简单匹配）
            if let matchIndex = existing.firstIndex(where: { isSimilar($0, entry) }) {
                // 已有类似知识：如果新的置信度更高或内容更丰富，则更新
                if entry.confidence > existing[matchIndex].confidence ||
                   entry.content.count > existing[matchIndex].content.count {
                    existing[matchIndex].content = entry.content
                    existing[matchIndex].confidence = max(existing[matchIndex].confidence, entry.confidence)
                    existing[matchIndex].updatedAt = .now
                    // 合并 tags
                    let newTags = Set(existing[matchIndex].tags).union(entry.tags)
                    existing[matchIndex].tags = Array(newTags)
                    updateCount += 1
                }
                // 否则保留已有的（已经足够好）
            } else {
                // 新知识，直接添加
                existing.append(entry)
                newCount += 1
            }
        }

        return (newCount, updateCount)
    }

    /// 相似度判断：同类别 + 内容字符级 n-gram 重叠 > 60%
    /// 支持中文（按字符 bigram）和英文（按空格分词）
    private func isSimilar(_ a: KnowledgeEntry, _ b: KnowledgeEntry) -> Bool {
        guard a.category == b.category else { return false }

        let tokensA = tokenize(a.content)
        let tokensB = tokenize(b.content)

        guard !tokensA.isEmpty, !tokensB.isEmpty else { return false }

        let overlap = tokensA.intersection(tokensB).count
        let similarity = Double(overlap) / Double(min(tokensA.count, tokensB.count))
        return similarity > 0.6
    }

    /// 混合分词：英文按空格分词，中文按字符 bigram
    private func tokenize(_ text: String) -> Set<String> {
        var tokens = Set<String>()
        // 空格分词（英文）
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { $0.count > 1 }
        tokens.formUnion(words)
        // 字符 bigram（中文友好）
        let chars = Array(text.filter { !$0.isWhitespace })
        for i in 0..<max(0, chars.count - 1) {
            tokens.insert(String(chars[i]) + String(chars[i + 1]))
        }
        return tokens
    }

    // MARK: - 文件读取

    private func readFileContent(_ url: URL) -> String? {
        FileTextExtractor.extractText(from: url)
    }
}
