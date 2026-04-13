import Foundation
import SwiftUI

/// 平台设置管理器 — 统一管理所有服务配置
@Observable
final class SettingsManager {
    // MARK: - LLM 配置
    var llmConfig: LLMConfig {
        didSet { save() }
    }

    // MARK: - 语音配置
    var voiceConfig: VoiceConfig {
        didSet { save() }
    }

    // MARK: - Obsidian 配置
    var obsidianConfig: ObsidianConfig {
        didSet { save() }
    }

    // MARK: - LLM Provider (缓存实例，配置变更时重建)
    private var _cachedProvider: OpenAICompatibleProvider?
    private var _cachedProviderConfig: LLMConfig?

    var llmProvider: (any LLMProvider)? {
        guard !llmConfig.apiKey.isEmpty else { return nil }
        if let cached = _cachedProvider, _cachedProviderConfig == llmConfig {
            return cached
        }
        let provider = OpenAICompatibleProvider(config: llmConfig)
        _cachedProvider = provider
        _cachedProviderConfig = llmConfig
        return provider
    }

    var isLLMConfigured: Bool {
        !llmConfig.apiKey.isEmpty && !llmConfig.endpoint.isEmpty
    }

    // MARK: - 初始化

    private static let storageKey = "aham_settings"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode(StoredSettings.self, from: data) {
            self.llmConfig = stored.llm
            self.voiceConfig = stored.voice
            self.obsidianConfig = stored.obsidian
        } else {
            self.llmConfig = .default
            self.voiceConfig = .default
            self.obsidianConfig = .default
        }
    }

    // MARK: - 持久化

    private func save() {
        let stored = StoredSettings(
            llm: llmConfig,
            voice: voiceConfig,
            obsidian: obsidianConfig
        )
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    /// 测试 LLM 连接
    func testLLMConnection() async -> Bool {
        guard let provider = llmProvider else { return false }
        return await provider.testConnection()
    }
}

// MARK: - 存储结构

private struct StoredSettings: Codable {
    let llm: LLMConfig
    let voice: VoiceConfig
    let obsidian: ObsidianConfig
}
