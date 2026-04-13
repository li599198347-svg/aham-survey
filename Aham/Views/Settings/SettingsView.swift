import SwiftUI

/// 全局设置页面 — TabView 分页布局
struct SettingsView: View {
    @Environment(SettingsManager.self) private var settings

    var body: some View {
        TabView {
            Tab("通用", systemImage: "gearshape") {
                GeneralSettingsTab()
            }

            Tab("语音与声纹", systemImage: "waveform") {
                VoiceSettingsTab()
            }

            Tab("知识库", systemImage: "brain") {
                KnowledgeSettingsTab()
            }

            Tab("导出", systemImage: "square.and.arrow.up") {
                ExportSettingsTab()
            }
        }
        .frame(width: 560, height: 460)
    }
}

// MARK: - 通用 Tab (AI 大模型)

private struct GeneralSettingsTab: View {
    @Environment(SettingsManager.self) private var settings
    @State private var testingConnection = false
    @State private var connectionResult: Bool?

    var body: some View {
        @Bindable var s = settings

        Form {
            Section("AI 大模型服务") {
                Picker("服务商", selection: $s.llmConfig.provider) {
                    Text("阿里百炼 (Dashscope)").tag("dashscope")
                    Text("OpenAI").tag("openai")
                    Text("自定义端点").tag("custom")
                }

                TextField("API 端点", text: $s.llmConfig.endpoint)
                    .textFieldStyle(.roundedBorder)

                SecureField("API Key", text: $s.llmConfig.apiKey)
                    .textFieldStyle(.roundedBorder)

                TextField("模型名称", text: $s.llmConfig.model)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button {
                        testConnection()
                    } label: {
                        if testingConnection {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("测试连接")
                        }
                    }
                    .disabled(testingConnection || !settings.isLLMConfigured)

                    if let result = connectionResult {
                        Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(result ? .green : .red)
                        Text(result ? "连接成功" : "连接失败")
                            .font(.caption)
                            .foregroundStyle(result ? .green : .red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            connectionResult = nil
            testingConnection = false
        }
    }

    private func testConnection() {
        testingConnection = true
        connectionResult = nil
        Task {
            let result = await settings.testLLMConnection()
            connectionResult = result
            testingConnection = false
        }
    }
}

// MARK: - 语音与声纹 Tab

private struct VoiceSettingsTab: View {
    @Environment(SettingsManager.self) private var settings

    var body: some View {
        @Bindable var s = settings

        Form {
            Section("语音服务") {
                Toggle("启用语音", isOn: $s.voiceConfig.enabled)

                if settings.voiceConfig.enabled {
                    Toggle("录音后自动转写", isOn: $s.voiceConfig.autoTranscribe)
                    Toggle("显示说话人标记", isOn: $s.voiceConfig.showSpeakers)

                    Text("使用 macOS 系统语音识别 + 声纹识别")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("声纹管理") {
                VoicePrintManagerView()
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 知识库 Tab

private struct KnowledgeSettingsTab: View {
    var body: some View {
        Form {
            Section {
                KnowledgeTrainingView()
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 导出 Tab (Obsidian)

private struct ExportSettingsTab: View {
    @Environment(SettingsManager.self) private var settings

    var body: some View {
        @Bindable var s = settings

        Form {
            Section("Obsidian 集成") {
                Toggle("启用 Obsidian", isOn: $s.obsidianConfig.enabled)

                if settings.obsidianConfig.enabled {
                    HStack {
                        TextField("Vault 路径", text: $s.obsidianConfig.vaultPath)
                            .textFieldStyle(.roundedBorder)
                        Button("选择...") {
                            selectVaultPath()
                        }
                    }

                    TextField("导出目录", text: $s.obsidianConfig.exportFolder)
                        .textFieldStyle(.roundedBorder)

                    Toggle("完成调研后自动导出", isOn: $s.obsidianConfig.autoExport)
                    Toggle("使用 [[wikilinks]]", isOn: $s.obsidianConfig.wikiLinks)
                    Toggle("添加 YAML Frontmatter", isOn: $s.obsidianConfig.addFrontmatter)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func selectVaultPath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "选择 Obsidian Vault 目录"
        if panel.runModal() == .OK, let url = panel.url {
            settings.obsidianConfig.vaultPath = url.path
            settings.obsidianConfig.vaultBookmark = ObsidianConfig.createBookmark(from: url)
        }
    }
}

#Preview {
    SettingsView()
        .environment(SettingsManager())
        .environment(VoicePrintStore())
        .environment(VoiceManager())
}
