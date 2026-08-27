import SwiftUI

public struct NetworkSettingsView: View {
    @ObservedObject public var engine: ShiftDownloadEngine

    public var body: some View {
        Form {
            Section("Concurrency & Connections") {
                Stepper("Max Concurrent Tasks: \(engine.settings.maxConcurrentDownloads)", value: Binding(
                    get: { engine.settings.maxConcurrentDownloads },
                    set: { engine.settings.maxConcurrentDownloads = $0 }
                ), in: 1...10)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Default Threads per Task")
                        Spacer()
                        Text("\(engine.settings.defaultConnectionsPerDownload) threads")
                            .foregroundColor(.blue)
                            .fontWeight(.bold)
                    }
                    Slider(value: Binding(
                        get: { Double(engine.settings.defaultConnectionsPerDownload) },
                        set: { engine.settings.defaultConnectionsPerDownload = Int($0) }
                    ), in: 1...32, step: 1)
                }
            }

            Section("Bandwidth Throttling") {
                Toggle("Global Speed Limiter", isOn: Binding(
                    get: { engine.settings.globalSpeedLimitEnabled },
                    set: {
                        engine.settings.globalSpeedLimitEnabled = $0
                        engine.updateSettings(engine.settings)
                    }
                ))

                if engine.settings.globalSpeedLimitEnabled {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Max Throughput")
                            Spacer()
                            Text(ByteCountFormatter.formatSpeed(bytesPerSecond: engine.settings.globalSpeedLimitBytesPerSec))
                                .font(.system(.subheadline, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                        }
                        Slider(value: Binding(
                            get: { Double(engine.settings.globalSpeedLimitBytesPerSec) / (1024 * 1024) },
                            set: {
                                engine.settings.globalSpeedLimitBytesPerSec = Int64($0 * 1024 * 1024)
                                engine.updateSettings(engine.settings)
                            }
                        ), in: 0.5...50.0, step: 0.5)
                    }
                }
            }

            Section(header: Text("Background Processing"), footer: Text("Keeps multi-stream downloads running continuously when locked or switching apps. Automatically shuts down when idle to conserve battery.")) {
                Toggle("Continuous Background Downloads", isOn: Binding(
                    get: { engine.settings.unrestrictedBackgroundDownloads },
                    set: {
                        engine.settings.unrestrictedBackgroundDownloads = $0
                        engine.updateSettings(engine.settings)
                    }
                ))
            }

            Section("Network Rules") {
                Toggle("Auto-Resume on Wi-Fi", isOn: $engine.settings.autoResumeOnWifi)
                Toggle("Allow Cellular Downloads", isOn: $engine.settings.allowCellularDownloads)
                Stepper("Retry Attempts on Error: \(engine.settings.retryCountOnFailure)", value: $engine.settings.retryCountOnFailure, in: 0...10)
            }
        }
        .navigationTitle("Network & Engine")
        .shiftInlineTitle()
    }
}

public struct SnifferSettingsView: View {
    @ObservedObject public var engine: ShiftDownloadEngine

    public var body: some View {
        Form {
            Section("Media Sniffer") {
                Toggle("Enable Universal Sniffer", isOn: $engine.settings.mediaSnifferEnabled)
                Toggle("Sniff Video Streams (MP4, WEBM)", isOn: $engine.settings.sniffVideos)
                Toggle("Sniff HLS Streams (M3U8)", isOn: $engine.settings.sniffHLSStreams)
                Toggle("Sniff Audio Tracks (MP3, AAC)", isOn: $engine.settings.sniffAudios)
                Toggle("Sniff Documents & Archives", isOn: $engine.settings.sniffDocuments)
                Toggle("Auto-Prompt on Media Detection", isOn: $engine.settings.autoPromptSniffedMedia)
            }

            Section("Web Browser") {
                Toggle("Ad & Tracker Blocker", isOn: $engine.settings.adBlockerEnabled)

                Picker("Default Search Engine", selection: $engine.settings.defaultSearchEngine) {
                    ForEach(SearchEngine.allCases) { engine in
                        Text(engine.rawValue).tag(engine)
                    }
                }

                Picker("User-Agent Preset", selection: $engine.settings.userAgentPreset) {
                    ForEach(UserAgentPreset.allCases) { ua in
                        Text(ua.rawValue).tag(ua)
                    }
                }

                if engine.settings.userAgentPreset == .custom {
                    TextField("Custom User-Agent String", text: $engine.settings.customUserAgent)
                }
            }
        }
        .navigationTitle("Sniffer & Browser")
        .shiftInlineTitle()
    }
}

public struct StorageSettingsView: View {
    @State private var breakdown: StorageBreakdown?
    @State private var showingClearAlert = false

    public var body: some View {
        Form {
            if let bd = breakdown {
                Section("Device Storage Overview") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Shift Storage Used")
                            Spacer()
                            Text(ByteCountFormatter.formatBytes(bd.appUsageBytes))
                                .fontWeight(.bold)
                        }

                        // Storage bar chart
                        GeometryReader { geo in
                            let total = max(1, bd.totalDiskSpace)
                            let shiftFraction = CGFloat(bd.appUsageBytes) / CGFloat(total)
                            let freeFraction = CGFloat(bd.freeDiskSpace) / CGFloat(total)
                            let otherFraction = max(0, 1.0 - shiftFraction - freeFraction)

                            HStack(spacing: 2) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.blue)
                                    .frame(width: max(4, geo.size.width * shiftFraction))
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.gray.opacity(0.4))
                                    .frame(width: max(4, geo.size.width * otherFraction))
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.green.opacity(0.4))
                                    .frame(width: max(4, geo.size.width * freeFraction))
                            }
                        }
                        .frame(height: 12)

                        HStack(spacing: 16) {
                            Label("Shift: \(ByteCountFormatter.formatBytes(bd.appUsageBytes))", systemImage: "circle.fill")
                                .font(.caption2)
                                .foregroundColor(.blue)
                            Label("Free: \(ByteCountFormatter.formatBytes(bd.freeDiskSpace))", systemImage: "circle.fill")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Storage Breakdown by Category") {
                    ForEach(TaskCategory.allCases.filter { $0 != .all }) { cat in
                        HStack {
                            Label(cat.displayName, systemImage: cat.iconName)
                                .foregroundColor(cat.color)
                            Spacer()
                            Text(ByteCountFormatter.formatBytes(bd.categoryBytes[cat] ?? 0))
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    showingClearAlert = true
                } label: {
                    Label("Clear All Downloaded Files", systemImage: "trash")
                }
            }
        }
        .navigationTitle("Storage & Cache")
        .shiftInlineTitle()
        .onAppear {
            self.breakdown = FileStorageService.shared.calculateStorageBreakdown()
        }
        .alert("Clear All Downloads?", isPresented: $showingClearAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                FileStorageService.shared.clearAllDownloads()
                self.breakdown = FileStorageService.shared.calculateStorageBreakdown()
            }
        } message: {
            Text("This will permanently remove all files downloaded with Shift.")
        }
    }
}
