# ADM — Advanced Download Manager (iOS 1DM & Gopeed Clone)

> High-Speed Multi-Threaded Download Manager for iOS with authentic stock Apple iOS UI (iOS 18+ / iOS 26 HIG).

---

## 📱 How to Open & Build in Xcode

### Method 1: Using the Native Xcode Project (`ADM.xcodeproj`) — **Recommended**
1. Double-click or open **`ADM.xcodeproj`** in Xcode:
   ```bash
   open ADM.xcodeproj
   ```
2. Select your target device or simulator (e.g. **iPhone 16 Pro / iOS 18+** or Any iOS Device).
3. Press **`Cmd + R`** (or click the Run button) to build and launch the app in the simulator or on your physical device!

### Method 2: Opening via Swift Package Manager
1. Open the project folder or `Package.swift` in Xcode:
   ```bash
   open Package.swift
   ```
2. Select the **`ShiftApp`** scheme.
3. Press **`Cmd + R`** to Run or **`Cmd + U`** to run the 14 unit test suites.

### Method 3: Command Line Build & Tests
```bash
# Run unit tests
swift test

# Build Xcode project for iOS Simulator
xcodebuild -project ADM.xcodeproj -scheme ADM -destination 'generic/platform=iOS Simulator' build
```

---

## ✨ Features & Capabilities

- **🚀 Multi-Threaded Range Engine**: Up to 32 concurrent chunk connections per download with dynamic chunk re-splitting and work-stealing.
- **🎬 Universal Media Sniffer & Browser**: Built-in Safari-style WebKit browser that sniffs and captures HLS (`.m3u8`), direct MP4/WEBM video, audio streams, documents, and archives in real-time.
- **⚡️ HLS Stream Downloader**: Downloads m3u8 master & variant streams concurrently and automatically stitches segments into clean `.mp4` video files.
- **🧲 BitTorrent & Magnet Link Support**: Decodes `magnet:?xt=urn:btih:...` links and `.torrent` bencoded files with piece tracking.
- **📊 Real-time Segment Visualizer & Speed Graph**: Visual multi-part thread progress bar (1DM hallmark) and live Bézier speed graph.
- **📦 Batch Pattern Downloader**: Expands URL ranges like `https://example.com/episodes/ep_[01-24].mp4` or `[a-z]`.
- **📁 Organized File Manager & AVPlayer**: Categorized folder system (Video, Audio, Docs, Archives, Torrents) with built-in Picture-in-Picture media player and Photos library export.
- **⚙️ 100% Stock Apple Settings UI**: Inset Grouped lists with granular controls for thread pools, global speed limits, ad-blocker rules, and cache cleaner.

---

## 🏗 Architecture & Code Layout

```
ADM.xcodeproj/                          # Native Xcode Project Bundle
├── project.pbxproj
└── xcshareddata/xcschemes/ADM.xcscheme

Sources/
├── ShiftAppTarget/
│   └── ShiftApplication.swift            # SwiftUI @main App Entrypoint
└── ADM/
    ├── App/
    │   ├── ShiftApp.swift                # Root View container
    │   └── AppEnvironment.swift        # Dependency injection & state persistence
    ├── Core/
    │   ├── Models/
    │   │   ├── DownloadTask.swift      # Download task entity with speed history
    │   │   ├── DownloadSegment.swift   # Chunk/thread offset state model
    │   │   ├── SniffedMedia.swift      # Extracted web media representation
    │   │   ├── TorrentMeta.swift       # Magnet link and torrent metadata
    │   │   ├── TaskCategory.swift      # Category enum & MIME detector
    │   │   └── AppSettings.swift       # User settings model
    │   ├── Engine/
    │   │   ├── ShiftDownloadEngine.swift # Central orchestrator & queue manager
    │   │   ├── ChunkedDownloader.swift # HTTP Range multi-thread downloader
    │   │   ├── HLSStreamDownloader.swift # m3u8 parser & segment stitcher
    │   │   ├── TorrentEngine.swift     # Magnet resolver & BitTorrent worker
    │   │   ├── SpeedLimiter.swift      # Token-bucket rate limiter
    │   │   └── BackgroundManager.swift # URLSession background delegate
    │   ├── Sniffer/
    │   │   ├── ShiftMediaSniffer.swift   # JavaScript injection & media sniffer
    │   │   └── ContentBlocker.swift    # AdBlock & Tracker blocker rules
    │   └── Storage/
    │       ├── TaskManager.swift       # JSON store persistence
    │       └── FileStorageService.swift# Category directories & storage breakdown
    └── UI/
        ├── MainTabView.swift           # Root TabBar (Downloads, Browser, Files, Settings)
        ├── Downloads/
        │   ├── DownloadsListView.swift # Filterable download list & speed ticker
        │   ├── DownloadRowView.swift   # Task card with multi-segment visualizer
        │   ├── DownloadDetailView.swift# Detailed task inspector & speed chart
        │   ├── NewDownloadSheet.swift  # URL modal & inspector
        │   └── BatchDownloadSheet.swift# Pattern URL generator
        ├── Browser/
        │   ├── BrowserView.swift       # WebKit browser with address bar
        │   ├── SnifferHUDView.swift    # Floating media sniffer badge & sheet
        │   └── BookmarksHistoryView.swift # Bookmarks and history list
        ├── Files/
        │   ├── FilesListView.swift     # Category pill carousel & file actions
        │   └── MediaPlayerView.swift   # AVPlayer with PiP & speed controls
        ├── Settings/
        │   ├── SettingsView.swift      # Apple Settings clone
        │   └── SubSettingsViews.swift  # Network, Sniffer, and Storage settings
        └── Components/
            ├── MultiSegmentProgressBar.swift # Multi-threaded chunk progress visualizer
            ├── SpeedChartView.swift    # Live Bézier speed curve
            ├── AppleStyleComponents.swift # Badges, pills, glass cards, haptics
            └── PlatformHelpers.swift   # Cross-platform modifiers & ShareSheet
```
