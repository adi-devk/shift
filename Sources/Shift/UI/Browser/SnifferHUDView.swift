import SwiftUI
import AVKit

public struct SnifferHUDView: View {
    @ObservedObject public var sniffer: ShiftMediaSniffer
    @ObservedObject public var engine: ShiftDownloadEngine

    @State private var isSheetPresented = false
    @State private var previewMedia: SniffedMedia?

    public init(sniffer: ShiftMediaSniffer, engine: ShiftDownloadEngine) {
        self.sniffer = sniffer
        self.engine = engine
    }

    public var body: some View {
        Group {
            if !sniffer.detectedMedia.isEmpty {
                Button {
                    HapticManager.triggerImpact(.light)
                    isSheetPresented = true
                } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.purple)
                                .frame(width: 24, height: 24)
                            Image(systemName: "sparkles.tv.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        }

                        Text("\(sniffer.detectedMedia.count) Media Found")
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)

                        Image(systemName: "chevron.up")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                    .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                }
                .sheet(isPresented: $isSheetPresented) {
                    SnifferMediaSheet(sniffer: sniffer, engine: engine, previewMedia: $previewMedia)
                }
                .sheet(item: $previewMedia) { media in
                    SnifferPreviewPlayerView(media: media)
                }
            }
        }
    }
}

public struct SnifferMediaSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var sniffer: ShiftMediaSniffer
    @ObservedObject public var engine: ShiftDownloadEngine
    @Binding public var previewMedia: SniffedMedia?

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(sniffer.detectedMedia) { item in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(item.mediaType.color.opacity(0.15))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: item.mediaType.iconName)
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundColor(item.mediaType.color)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .font(.headline)
                                        .lineLimit(2)

                                    HStack(spacing: 6) {
                                        Text(item.format)
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.purple.opacity(0.15))
                                            .foregroundColor(.purple)
                                            .cornerRadius(4)

                                        if let res = item.resolution {
                                            Text(res)
                                                .font(.caption2)
                                                .fontWeight(.medium)
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()

                                        Text(item.formattedSize)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }

                            // Quick Action Buttons
                            HStack(spacing: 8) {
                                Button {
                                    startDownload(media: item, audioOnly: false)
                                } label: {
                                    Label("Download", systemImage: "arrow.down.circle.fill")
                                        .font(.footnote)
                                        .fontWeight(.semibold)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.blue)

                                if item.mediaType == .video || item.mediaType == .hlsStream {
                                    Button {
                                        startDownload(media: item, audioOnly: true)
                                    } label: {
                                        Label("Audio", systemImage: "music.note")
                                            .font(.footnote)
                                            .padding(.vertical, 6)
                                    }
                                    .buttonStyle(.bordered)
                                }

                                Button {
                                    previewMedia = item
                                } label: {
                                    Image(systemName: "play.circle")
                                        .font(.system(size: 16))
                                        .padding(6)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Detected Streams & Media (\(sniffer.detectedMedia.count))")
                }
            }
            .shiftListStyle()
            .navigationTitle("Media Sniffer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear All") {
                        sniffer.clear()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func startDownload(media: SniffedMedia, audioOnly: Bool) {
        HapticManager.triggerNotification(.success)
        let ext = audioOnly ? "m4a" : (media.format.lowercased() == "m3u8" ? "mp4" : media.format.lowercased())
        let safeTitle = media.title.replacingOccurrences(of: "/", with: "_")
        let fileName = "\(safeTitle).\(ext)"

        if media.mediaType == .hlsStream || media.url.absoluteString.contains(".m3u8") {
            _ = engine.addHLSTask(url: media.url, fileName: fileName, headers: media.headers)
        } else {
            _ = engine.addDownloadTask(
                url: media.url,
                fileName: fileName,
                category: audioOnly ? .audio : TaskCategory.determineCategory(from: fileName),
                headers: media.headers
            )
        }

        dismiss()
    }
}

public struct SnifferPreviewPlayerView: View {
    public let media: SniffedMedia
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationStack {
            VideoPlayer(player: AVPlayer(url: media.url))
                .ignoresSafeArea()
                .navigationTitle(media.title)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
