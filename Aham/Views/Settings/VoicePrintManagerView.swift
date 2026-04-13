import SwiftUI
import AVFoundation

/// 声纹管理视图 — 在设置中注册/管理/测试声纹
struct VoicePrintManagerView: View {
    @Environment(VoicePrintStore.self) private var store
    @Environment(VoiceManager.self) private var voiceManager

    @State private var showRegisterSheet = false
    @State private var showTestSheet = false
    @State private var testTargetId: String?
    @State private var showDeleteConfirm = false
    @State private var deleteTargetId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 标题行
            HStack {
                Text("注册说话人声纹后，录音时可自动识别发言者身份")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showRegisterSheet = true
                } label: {
                    Label("注册声纹", systemImage: "plus")
                }
                .controlSize(.small)
            }

            if store.voicePrints.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "waveform.badge.plus")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                        Text("暂无声纹")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 16)
                    Spacer()
                }
            } else {
                ForEach(store.voicePrints) { vp in
                    voicePrintRow(vp)
                }
            }
        }
        .sheet(isPresented: $showRegisterSheet) {
            VoicePrintRegisterSheet()
        }
        .sheet(isPresented: $showTestSheet) {
            if let id = testTargetId {
                VoicePrintTestSheet(voicePrintId: id)
            }
        }
        .alert("确认删除", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let id = deleteTargetId {
                    store.delete(id: id)
                }
            }
        } message: {
            Text("删除后无法恢复，确定要删除这个声纹吗？")
        }
    }

    // MARK: - 声纹行

    @ViewBuilder
    private func voicePrintRow(_ vp: VoicePrint) -> some View {
        HStack(spacing: 10) {
            Image(systemName: vp.role.icon)
                .font(.body)
                .foregroundStyle(roleColor(vp.role))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(vp.name)
                    .font(.callout)
                    .fontWeight(.medium)
                HStack(spacing: 6) {
                    Text(vp.role.label)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(roleColor(vp.role).opacity(0.1), in: .capsule)
                        .foregroundStyle(roleColor(vp.role))
                    Text("\(vp.sampleCount) 个样本")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(vp.createdAt, format: .dateTime.month().day())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // 测试
            Button {
                testTargetId = vp.id
                showTestSheet = true
            } label: {
                Label("测试", systemImage: "mic.badge.xmark")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            // 删除
            Button {
                deleteTargetId = vp.id
                showDeleteConfirm = true
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
        }
        .padding(.vertical, 2)
    }

    private func roleColor(_ role: VoicePrintRole) -> Color {
        switch role {
        case .consultant: .blue
        case .customer: .green
        case .other: .secondary
        }
    }
}

// MARK: - 声纹注册弹窗

struct VoicePrintRegisterSheet: View {
    @Environment(VoicePrintStore.self) private var store
    @Environment(VoiceManager.self) private var voiceManager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var role: VoicePrintRole = .customer
    @State private var isRecording = false
    @State private var recordedSamples: [Float] = []
    @State private var recordingDuration: TimeInterval = 0

    var body: some View {
        VStack(spacing: 20) {
            // 标题
            Text("注册新声纹")
                .font(.headline)

            // 表单
            Form {
                TextField("姓名", text: $name)
                Picker("角色", selection: $role) {
                    ForEach(VoicePrintRole.allCases) { r in
                        Text(r.label).tag(r)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(height: 100)
            .scrollDisabled(true)

            // 录音区域
            VStack(spacing: 12) {
                // 音量指示
                ZStack {
                    Circle()
                        .stroke(.quaternary, lineWidth: 3)
                        .frame(width: 80, height: 80)

                    if isRecording {
                        Circle()
                            .trim(from: 0, to: min(recordingDuration / 10, 1))
                            .stroke(Color.red, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: 80, height: 80)
                            .rotationEffect(.degrees(-90))

                        Circle()
                            .fill(.red.opacity(0.15))
                            .frame(width: 60, height: 60)
                            .scaleEffect(1.0 + CGFloat(voiceManager.capture.currentLevel) * 0.4)
                            .animation(.easeOut(duration: 0.1), value: voiceManager.capture.currentLevel)
                    }

                    Image(systemName: isRecording ? "mic.fill" : "mic")
                        .font(.title2)
                        .foregroundStyle(isRecording ? .red : .secondary)
                }

                if isRecording {
                    Text(String(format: "%.1f 秒", recordingDuration))
                        .font(.title3)
                        .monospacedDigit()
                        .foregroundStyle(.red)
                } else if !recordedSamples.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("已录制 \(String(format: "%.1f", recordingDuration)) 秒")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("请在安静环境下录制 5-10 秒自然语音")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                // 录音按钮
                Button {
                    if isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                } label: {
                    Text(isRecording ? "停止录音" : (recordedSamples.isEmpty ? "开始录音" : "重新录音"))
                        .frame(width: 120)
                }
                .controlSize(.large)
                .buttonStyle(.bordered)
                .tint(isRecording ? .red : .accentColor)
            }

            Spacer()

            // 底部按钮
            HStack {
                Button("取消") {
                    if isRecording {
                        voiceManager.cancelRecording()
                    }
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("保存") {
                    completeRegistration()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || recordedSamples.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360, height: 420)
    }

    private func startRecording() {
        Task {
            do {
                try await voiceManager.startRecording(autoTranscribe: false)
                isRecording = true
                recordingDuration = 0
                recordedSamples = []
            } catch {
                print("[VoicePrint] Recording error: \(error)")
            }
        }
    }

    private func stopRecording() {
        let result = voiceManager.stopRecording()
        isRecording = false
        recordingDuration = result.duration
        let buffer = voiceManager.capture.lastRecordingBuffer
        if !buffer.isEmpty {
            recordedSamples = buffer
        }
    }

    private func completeRegistration() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              !recordedSamples.isEmpty else { return }
        _ = store.register(
            name: name.trimmingCharacters(in: .whitespaces),
            role: role,
            audioSamples: recordedSamples
        )
    }
}

// MARK: - 声纹测试弹窗

struct VoicePrintTestSheet: View {
    let voicePrintId: String

    @Environment(VoicePrintStore.self) private var store
    @Environment(VoiceManager.self) private var voiceManager
    @Environment(\.dismiss) private var dismiss

    @State private var isRecording = false
    @State private var testResult: Float?
    @State private var addingSample = false

    private var voicePrint: VoicePrint? {
        store.voicePrints.first { $0.id == voicePrintId }
    }

    var body: some View {
        VStack(spacing: 20) {
            if let vp = voicePrint {
                // 标题
                Text("测试声纹 - \(vp.name)")
                    .font(.headline)

                // 状态信息
                HStack(spacing: 8) {
                    Text(vp.role.label)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(roleColor(vp.role).opacity(0.1), in: .capsule)
                        .foregroundStyle(roleColor(vp.role))
                    Text("\(vp.sampleCount) 个样本")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // 录音/结果区域
                VStack(spacing: 16) {
                    if let result = testResult {
                        // 匹配结果
                        let matched = result >= SpeakerEmbedding.matchThreshold
                        ZStack {
                            Circle()
                                .stroke(matched ? Color.green : Color.red, lineWidth: 4)
                                .frame(width: 80, height: 80)
                            VStack(spacing: 2) {
                                Image(systemName: matched ? "checkmark" : "xmark")
                                    .font(.title2)
                                    .foregroundStyle(matched ? .green : .red)
                                Text(String(format: "%.0f%%", result * 100))
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .monospacedDigit()
                            }
                        }

                        Text(matched ? "匹配成功" : "匹配失败")
                            .font(.callout)
                            .fontWeight(.medium)
                            .foregroundStyle(matched ? .green : .red)

                        Text("相似度阈值: \(String(format: "%.0f%%", SpeakerEmbedding.matchThreshold * 100))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        // 录音指示
                        ZStack {
                            Circle()
                                .stroke(.quaternary, lineWidth: 3)
                                .frame(width: 80, height: 80)
                            if isRecording {
                                Circle()
                                    .fill(.red.opacity(0.15))
                                    .frame(width: 60, height: 60)
                                    .scaleEffect(1.0 + CGFloat(voiceManager.capture.currentLevel) * 0.4)
                                    .animation(.easeOut(duration: 0.1), value: voiceManager.capture.currentLevel)
                            }
                            Image(systemName: isRecording ? "mic.fill" : "mic")
                                .font(.title2)
                                .foregroundStyle(isRecording ? .red : .secondary)
                        }

                        Text(isRecording ? "正在录音..." : "录制一段语音来测试匹配")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // 操作按钮
                HStack(spacing: 12) {
                    if testResult == nil {
                        Button {
                            if isRecording {
                                stopTestRecording()
                            } else {
                                startTestRecording()
                            }
                        } label: {
                            Text(isRecording ? "停止" : "开始测试")
                                .frame(width: 100)
                        }
                        .controlSize(.large)
                        .buttonStyle(.bordered)
                        .tint(isRecording ? .red : .accentColor)
                    } else {
                        Button("重新测试") {
                            testResult = nil
                        }
                        .controlSize(.large)
                        .buttonStyle(.bordered)

                        Button("追加样本") {
                            addSample()
                        }
                        .controlSize(.large)
                        .buttonStyle(.bordered)
                        .tint(.orange)
                        .help("将本次录音追加为训练样本，提高识别准确度")
                    }

                    Spacer()

                    Button("关闭") {
                        if isRecording {
                            voiceManager.cancelRecording()
                        }
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(24)
        .frame(width: 340, height: 380)
    }

    private func startTestRecording() {
        testResult = nil
        Task {
            do {
                try await voiceManager.startRecording(autoTranscribe: false)
                isRecording = true
            } catch {
                print("[VoicePrint] Test error: \(error)")
            }
        }
    }

    private func stopTestRecording() {
        _ = voiceManager.stopRecording()
        isRecording = false
        let buffer = voiceManager.capture.lastRecordingBuffer
        guard !buffer.isEmpty else { return }
        testResult = store.testMatch(audioSamples: buffer, voicePrintId: voicePrintId)
    }

    private func addSample() {
        let buffer = voiceManager.capture.lastRecordingBuffer
        guard !buffer.isEmpty else { return }
        store.addSample(to: voicePrintId, audioSamples: buffer)
        testResult = nil
    }

    private func roleColor(_ role: VoicePrintRole) -> Color {
        switch role {
        case .consultant: .blue
        case .customer: .green
        case .other: .secondary
        }
    }
}
