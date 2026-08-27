import Foundation
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
public final class BackgroundDownloadService: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    public static let shared = BackgroundDownloadService()

    private var audioPlayer: AVAudioPlayer?
    private var isAudioKeepAliveActive = false
    #if os(iOS)
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
    #endif

    private override init() {
        super.init()
    }

    /// Dynamically activates or shuts down background services based on active download count and user settings.
    /// When 0 downloads are active, completely shuts down to guarantee ZERO background battery drain.
    public func updateActiveState(hasActiveDownloads: Bool, isEnabled: Bool) {
        if hasActiveDownloads && isEnabled {
            startBackgroundKeepAlive()
        } else {
            stopBackgroundKeepAlive()
        }
    }

    private func startBackgroundKeepAlive() {
        guard !isAudioKeepAliveActive else { return }
        isAudioKeepAliveActive = true
        ShiftLogger.shared.info("⚡️ Background keepalive activated (.mixWithOthers silent session)", category: .background)

        #if os(iOS)
        beginAppleBackgroundTask()
        startSilentAudioSession()
        #endif
    }

    private func stopBackgroundKeepAlive() {
        guard isAudioKeepAliveActive else { return }
        isAudioKeepAliveActive = false
        ShiftLogger.shared.info("💤 Background keepalive deactivated. Audio released (0% idle battery).", category: .background)

        // Stop audio playback
        if let player = audioPlayer {
            player.stop()
            audioPlayer = nil
        }

        #if os(iOS)
        // Deactivate audio session to release hardware and save 100% battery
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Ignore if already inactive
        }

        endAppleBackgroundTask()
        #endif
    }

    #if os(iOS)
    private func beginAppleBackgroundTask() {
        endAppleBackgroundTask()
        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(withName: "com.shift.download.active") { [weak self] in
            Task { @MainActor [weak self] in
                self?.endAppleBackgroundTask()
            }
        }
    }

    private func endAppleBackgroundTask() {
        if backgroundTaskIdentifier != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
            backgroundTaskIdentifier = .invalid
        }
    }

    private func startSilentAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // Set playback category with .mixWithOthers so other media (YouTube, Spotify, etc.) is NEVER interrupted
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            if audioPlayer == nil {
                let silentData = createSilentAudioWAVData()
                let player = try AVAudioPlayer(data: silentData)
                player.numberOfLoops = -1 // Infinite non-stop loop
                player.volume = 0.0 // 100% silent
                player.delegate = self
                player.prepareToPlay()
                player.play()
                self.audioPlayer = player
            } else {
                self.audioPlayer?.play()
            }
        } catch {
            // Fallback gracefully without throwing
        }
    }
    #endif

    /// Generates a minimal 1-second silent 16-bit 44.1kHz PCM WAV file in memory
    private func createSilentAudioWAVData() -> Data {
        let sampleRate: Int32 = 44100
        let numChannels: Int16 = 1
        let bitsPerSample: Int16 = 16
        let durationSeconds: Int = 1
        let numSamples = Int(sampleRate) * durationSeconds
        let dataSize = Int32(numSamples * Int(numChannels) * Int(bitsPerSample / 8))
        let totalSize = dataSize + 36

        var data = Data()
        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: totalSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)

        // fmt subchunk
        data.append(contentsOf: "fmt ".utf8)
        let subchunk1Size: Int32 = 16
        let audioFormat: Int16 = 1 // PCM
        let byteRate: Int32 = sampleRate * Int32(numChannels) * Int32(bitsPerSample / 8)
        let blockAlign: Int16 = numChannels * (bitsPerSample / 8)

        data.append(contentsOf: withUnsafeBytes(of: subchunk1Size.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: audioFormat.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })

        // data subchunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

        // Zeroes for silent PCM audio
        data.append(Data(count: Int(dataSize)))

        return data
    }
}
