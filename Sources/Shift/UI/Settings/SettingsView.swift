import SwiftUI

public struct SettingsView: View {
    @ObservedObject public var engine: ShiftDownloadEngine
    @State private var showSecretDiagnostics = false
    @State private var secretTapCount = 0

    public init(engine: ShiftDownloadEngine) {
        self.engine = engine
    }

    public var body: some View {
        NavigationStack {
            Form {
                // Header profile card
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 54, height: 54)
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.white)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Shift - Download Manager")
                                .font(.headline)
                                .fontWeight(.bold)
                            Text("High-Speed Multi-Thread Download Engine")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Core configuration links
                Section {
                    NavigationLink(destination: NetworkSettingsView(engine: engine)) {
                        Label {
                            VStack(alignment: .leading) {
                                Text("Network & Engine")
                                Text("\(engine.settings.defaultConnectionsPerDownload) Threads • Max \(engine.settings.maxConcurrentDownloads) Tasks")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "network")
                                .foregroundColor(.blue)
                        }
                    }

                    NavigationLink(destination: SnifferSettingsView(engine: engine)) {
                        Label {
                            VStack(alignment: .leading) {
                                Text("Sniffer & Browser")
                                Text("AdBlock • Video/HLS Stream Interceptor")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "sparkles.tv")
                                .foregroundColor(.purple)
                        }
                    }

                    NavigationLink(destination: StorageSettingsView()) {
                        Label {
                            VStack(alignment: .leading) {
                                Text("Storage & Cache")
                                Text("Organized Directories • Disk Usage")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "internaldrive")
                                .foregroundColor(.orange)
                        }
                    }
                }

                // BitTorrent preferences
                Section("BitTorrent & P2P") {
                    HStack {
                        Text("Listening Port")
                        Spacer()
                        Text("\(engine.settings.torrentListeningPort)")
                            .foregroundColor(.secondary)
                    }

                    Toggle("DHT Network Enabled", isOn: $engine.settings.torrentDHTEnabled)
                    Stepper("Max Peers: \(engine.settings.torrentMaxPeers)", value: $engine.settings.torrentMaxPeers, in: 10...200)
                }

                // System & Feedback
                Section("System & Notifications") {
                    Toggle("Notification on Completion", isOn: $engine.settings.notifyOnCompletion)
                    Toggle("Haptic Touch Feedback", isOn: $engine.settings.hapticFeedbackEnabled)
                    Toggle("Auto-Detect Clipboard Links", isOn: $engine.settings.autoClipboardDetect)
                }

                // About & Credits (with secret 5-tap developer trigger)
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("2.6.0 (Build 108)")
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        secretTapCount += 1
                        if secretTapCount >= 5 {
                            secretTapCount = 0
                            HapticManager.triggerNotification(.success)
                            showSecretDiagnostics = true
                        }
                    }

                    LabeledContent("Core Engine", value: "Swift Concurrency + Gopeed Core")
                    LabeledContent("Platform", value: "iOS 18+ / iOS 26 HIG")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showSecretDiagnostics) {
                NavigationStack {
                    DiagnosticsLogView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    showSecretDiagnostics = false
                                }
                            }
                        }
                }
            }
        }
    }
}
