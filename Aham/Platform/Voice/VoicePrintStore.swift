import Foundation

/// 声纹数据持久化 + 匹配服务
@Observable
@MainActor
final class VoicePrintStore {
    private(set) var voicePrints: [VoicePrint] = []
    private let storePath: URL
    private let embedding = SpeakerEmbedding()

    init() {
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let dir = appSupport.appendingPathComponent("Aham/VoicePrints", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            storePath = dir.appendingPathComponent("voiceprints.json")
        } else {
            storePath = FileManager.default.temporaryDirectory.appendingPathComponent("voiceprints.json")
        }
        load()
    }

    // MARK: - 注册

    /// 从音频样本注册新声纹
    func register(name: String, role: VoicePrintRole, company: String = "",
                  audioSamples: [Float], captureSampleRate: Double = 16000) -> VoicePrint {
        let emb = embedding.extractEmbedding(from: audioSamples,
                                              captureSampleRate: captureSampleRate)
        let vp = VoicePrint(name: name, role: role, company: company, embedding: emb)
        voicePrints.append(vp)
        save()
        return vp
    }

    /// 从会议转写标注中注册声纹（已有嵌入向量，无需重新提取）
    func registerFromMeetingSegment(name: String, role: VoicePrintRole, company: String = "", embedding emb: [Float]) -> VoicePrint {
        // 若同名声纹已存在则追加样本（取平均）
        if let idx = voicePrints.firstIndex(where: { $0.name == name }) {
            let averaged = SpeakerEmbedding.averageEmbeddings([voicePrints[idx].embedding, emb])
            voicePrints[idx].embedding = averaged
            voicePrints[idx].sampleCount += 1
            voicePrints[idx].updatedAt = .now
            save()
            return voicePrints[idx]
        }
        let vp = VoicePrint(name: name, role: role, company: company, embedding: emb)
        voicePrints.append(vp)
        save()
        return vp
    }

    /// 追加录音样本到已有声纹 (取平均)
    func addSample(to voicePrintId: String, audioSamples: [Float],
                   captureSampleRate: Double = 16000) {
        guard let idx = voicePrints.firstIndex(where: { $0.id == voicePrintId }) else { return }
        let newEmb = embedding.extractEmbedding(from: audioSamples,
                                                 captureSampleRate: captureSampleRate)
        let averaged = SpeakerEmbedding.averageEmbeddings([voicePrints[idx].embedding, newEmb])
        voicePrints[idx].embedding = averaged
        voicePrints[idx].sampleCount += 1
        voicePrints[idx].updatedAt = .now
        save()
    }

    // MARK: - 删除

    func delete(id: String) {
        voicePrints.removeAll { $0.id == id }
        save()
    }

    func deleteAll() {
        voicePrints.removeAll()
        save()
    }

    // MARK: - 匹配

    /// 从音频样本识别说话人
    func identify(audioSamples: [Float], captureSampleRate: Double = 16000) -> SpeakerMatch? {
        guard !voicePrints.isEmpty else { return nil }

        let queryEmb = embedding.extractEmbedding(from: audioSamples,
                                                   captureSampleRate: captureSampleRate)
        return match(embedding: queryEmb)
    }

    /// 从嵌入向量匹配最近的声纹
    func match(embedding queryEmb: [Float]) -> SpeakerMatch? {
        guard !voicePrints.isEmpty else { return nil }

        var bestMatch: SpeakerMatch?
        var bestSimilarity: Float = -1

        for vp in voicePrints {
            let sim = SpeakerEmbedding.cosineSimilarity(queryEmb, vp.embedding)
            if sim > bestSimilarity {
                bestSimilarity = sim
                bestMatch = SpeakerMatch(
                    voicePrint: vp,
                    similarity: sim,
                    isConfident: sim >= SpeakerEmbedding.matchThreshold
                )
            }
        }

        return bestMatch
    }

    /// 测试音频是否匹配指定声纹
    func testMatch(audioSamples: [Float], voicePrintId: String,
                   captureSampleRate: Double = 16000) -> Float {
        guard let vp = voicePrints.first(where: { $0.id == voicePrintId }) else { return 0 }
        let queryEmb = embedding.extractEmbedding(from: audioSamples,
                                                   captureSampleRate: captureSampleRate)
        return SpeakerEmbedding.cosineSimilarity(queryEmb, vp.embedding)
    }

    // MARK: - 更新

    func updateName(_ name: String, for id: String) {
        guard let idx = voicePrints.firstIndex(where: { $0.id == id }) else { return }
        voicePrints[idx].name = name
        voicePrints[idx].updatedAt = .now
        save()
    }

    func updateRole(_ role: VoicePrintRole, for id: String) {
        guard let idx = voicePrints.firstIndex(where: { $0.id == id }) else { return }
        voicePrints[idx].role = role
        voicePrints[idx].updatedAt = .now
        save()
    }

    func updateCompany(_ company: String, for id: String) {
        guard let idx = voicePrints.firstIndex(where: { $0.id == id }) else { return }
        voicePrints[idx].company = company
        voicePrints[idx].updatedAt = .now
        save()
    }

    // MARK: - 持久化

    private func load() {
        guard FileManager.default.fileExists(atPath: storePath.path),
              let data = try? Data(contentsOf: storePath),
              let decoded = try? JSONDecoder.voicePrint.decode([VoicePrint].self, from: data) else {
            return
        }
        voicePrints = decoded
    }

    private func save() {
        do {
            let data = try JSONEncoder.voicePrint.encode(voicePrints)
            try data.write(to: storePath, options: .atomic)
        } catch {
            print("[VoicePrintStore] Save failed: \(error)")
        }
    }
}

// MARK: - JSON Coding

private extension JSONDecoder {
    static let voicePrint: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private extension JSONEncoder {
    static let voicePrint: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        return encoder
    }()
}
