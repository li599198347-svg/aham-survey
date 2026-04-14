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

    // MARK: - 金蝶云星空配置
    var kingdeeConfig: KingdeeConfig {
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
            self.kingdeeConfig = stored.kingdee ?? .default
        } else {
            self.llmConfig = .default
            self.voiceConfig = .default
            self.obsidianConfig = .default
            self.kingdeeConfig = .default
        }
    }

    // MARK: - 持久化

    private func save() {
        let stored = StoredSettings(
            llm: llmConfig,
            voice: voiceConfig,
            obsidian: obsidianConfig,
            kingdee: kingdeeConfig
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
    var kingdee: KingdeeConfig?
}

// MARK: - 金蝶云星空配置模型

struct KingdeeConfig: Codable, Equatable {
    /// 金蝶服务器地址，如 http://192.168.0.214
    var serverURL: String
    /// 账套 ID
    var acctId: String
    /// 登录用户名
    var username: String
    /// App ID
    var appId: String
    /// App Secret
    var appSecret: String
    /// 语言 ID（2052 = 简体中文）
    var lcid: String

    var isConfigured: Bool {
        !serverURL.isEmpty && !acctId.isEmpty && !appId.isEmpty && !appSecret.isEmpty
    }

    static let `default` = KingdeeConfig(
        serverURL: "http://192.168.0.214/k3cloud",
        acctId: "653b74cbc16075",
        username: "李成豹",
        appId: "339203_5f0rwwsP3oDW049L51SCV+wF2uR81BtO",
        appSecret: "4429d2a7b66348099f3f7ed039161f81",
        lcid: "2052"
    )
}
