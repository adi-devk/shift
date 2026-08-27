# Shift ⚡️

> High-speed multi-threaded download manager and Safari-grade media browser for iOS. Built natively in SwiftUI with authentic Apple HIG design.

[![iOS 17.0+](https://img.shields.io/badge/iOS-17.0%2B-blue.svg?style=flat&logo=apple)](https://developer.apple.com/ios/)
[![Swift 5.10 / 6.0](https://img.shields.io/badge/Swift-5.10%20%2F%206.0-orange.svg?style=flat&logo=swift)](https://swift.org)
[![Xcode 15 / 16](https://img.shields.io/badge/Xcode-15%20%2F%2016-blue.svg?style=flat&logo=xcode)](https://developer.apple.com/xcode/)
[![Tests](https://img.shields.io/badge/Tests-24%20Passing-brightgreen.svg?style=flat)](Tests/)
[![License](https://img.shields.io/badge/License-MIT-green.svg?style=flat)](LICENSE)

---

## ✨ Features

- 🚀 **Multi-Threaded Acceleration**: Up to 32 concurrent Range connections per task with dynamic chunk re-allocation and zero-gap file stitching.
- 🌐 **Universal Resource Recognition**: Automatic resolver engine inspired by Gopeed — supports direct links, **Google Drive** (with automatic virus scan bypass & 8–16 threads), **Dropbox**, **GitHub Releases/Raw**, and 100+ MIME types.
- 🔄 **Refresh Expired Links**: Easily update expired temporary download URLs without losing previously downloaded progress or bytes.
- 📱 **Live Home Screen Widget**: Small, Medium, and Large widgets with edge-to-edge compact design and real-time background timeline extrapolation.
- 🌍 **Multi-Tab Web Browser**: Full Safari-style browser with a 2-column tab switcher, private browsing, `aA` page tools, persistent search engines, and built-in media sniffer.
- 🎬 **HLS Stream Downloader**: Downloads `.m3u8` master and variant streams concurrently and stitches segments into `.mp4` video files.
- 🧲 **BitTorrent & Magnet**: Supports `.torrent` files and `magnet:?xt=urn:btih:...` URIs with piece verification.
- 🔋 **Battery-Conscious Backgrounding**: Intelligent low-power background keepalive that only runs while active downloads are in progress.
- 📁 **Built-in File Manager & Media Player**: Automatic categorization, PiP-enabled AVPlayer, and one-tap export to iOS Photos / Files.

---

## 🚀 Quick Start

### 1. Build in Xcode
```bash
open Shift.xcodeproj
```
Select the **`Shift`** scheme and your target iOS device or Simulator, then press **`Cmd + R`**.

### 2. Package `.ipa` for Sideloading (TrollStore / AltStore / SideStore)
```bash
./make_ipa.sh
```
The output `.ipa` will be generated at `Shift.ipa`.

### 3. Run Tests
```bash
swift test
```

---

## 🛠 Tech Stack & Requirements

- **Platform**: iOS 17.0+
- **Language**: Swift 5.10 / Swift 6 (Strict Concurrency ready)
- **UI Framework**: SwiftUI + WidgetKit + WebKit
- **Architecture**: Modular MVVM + Reactive Combine Engine

---

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
