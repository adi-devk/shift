import SwiftUI
import AVKit

public struct MediaPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    public let fileURL: URL
    public let title: String

    @State private var player: AVPlayer?
    @State private var playbackRate: Float = 1.0

    public init(fileURL: URL, title: String? = nil) {
        self.fileURL = fileURL
        self.title = title ?? fileURL.lastPathComponent
    }

    public var body: some View {
        NavigationStack {
            VStack {
                if let p = player {
                    VideoPlayer(player: p) {
                        // Custom overlay controls
                    }
                    .ignoresSafeArea(edges: .bottom)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(title)
            .shiftInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Menu {
                        Button("0.5x") { setRate(0.5) }
                        Button("0.75x") { setRate(0.75) }
                        Button("1.0x (Normal)") { setRate(1.0) }
                        Button("1.25x") { setRate(1.25) }
                        Button("1.5x") { setRate(1.5) }
                        Button("2.0x") { setRate(2.0) }
                    } label: {
                        Text("\(String(format: "%.2fx", playbackRate))")
                            .font(.system(.footnote, design: .monospaced))
                            .fontWeight(.semibold)
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        player?.pause()
                        dismiss()
                    }
                }
            }
            .onAppear {
                let avPlayer = AVPlayer(url: fileURL)
                self.player = avPlayer
                avPlayer.play()
            }
            .onDisappear {
                player?.pause()
            }
        }
    }

    private func setRate(_ rate: Float) {
        playbackRate = rate
        player?.rate = rate
    }
}
