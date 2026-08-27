import SwiftUI

public struct NewDownloadSheet: View {
    @Environment(\.dismiss) private var dismiss
    public let engine: ShiftDownloadEngine

    @State private var urlString = ""
    @State private var customFileName = ""
    @State private var selectedCategory: TaskCategory = .all
    @State private var maxConnections: Double = 8
    
    @State private var isProbing = false
    @State private var probeResult: ChunkedDownloader.ProbeResult?
    @State private var probeError: String?

    @State private var showAdvancedHeaders = false
    @State private var referer = ""
    @State private var cookie = ""
    @State private var authorization = ""
    @State private var customUserAgent = ""

    // Duplicate detection alert states
    @State private var showDuplicateAlert = false
    @State private var duplicateFileName = ""

    public init(engine: ShiftDownloadEngine, initialURL: String = "") {
        self.engine = engine
        _urlString = State(initialValue: initialURL)
    }

    private var effectiveFileName: String {
        let trimmed = customFileName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty && trimmed != "view" && trimmed != "uc" && trimmed != "open" {
            return trimmed
        }
        if let suggested = probeResult?.suggestedFileName, !suggested.isEmpty {
            return suggested
        }
        if let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) {
            let last = url.lastPathComponent
            if !last.isEmpty && last != "view" && last != "uc" && last != "open" {
                return last
            }
            if GoogleDriveURLResolver.isGoogleDriveURL(url) {
                return "GoogleDrive_File_\(Int(Date().timeIntervalSince1970))"
            }
        }
        return "download_\(Int(Date().timeIntervalSince1970))"
    }

    private var isDuplicatePresent: Bool {
        let name = effectiveFileName
        let cat = selectedCategory == .all ? TaskCategory.determineCategory(from: name) : selectedCategory
        let taskDup = engine.findExistingTask(fileName: name) != nil
        let fileDup = FileStorageService.shared.fileExists(fileName: name, category: cat)
        return taskDup || fileDup
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Download URL") {
                    HStack {
                        TextField("https://example.com/file.zip", text: $urlString)
                            .shiftNoAutocapitalization()
                            .autocorrectionDisabled()
                            .onChange(of: urlString) { _ in
                                autoPopulateFileName()
                            }

                        if !urlString.isEmpty {
                            Button {
                                urlString = ""
                                customFileName = ""
                                probeResult = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        Button {
                            if let paste = ClipboardHelper.text {
                                urlString = paste.trimmingCharacters(in: .whitespacesAndNewlines)
                                autoPopulateFileName()
                                probeCurrentURL()
                            }
                        } label: {
                            Label("Paste Link", systemImage: "doc.on.clipboard")
                                .font(.footnote)
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button {
                            probeCurrentURL()
                        } label: {
                            if isProbing {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Label("Inspect URL", systemImage: "sparkle.magnifyingglass")
                                    .font(.footnote)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(urlString.isEmpty || isProbing)
                    }
                }

                if let probe = probeResult {
                    Section("URL Details") {
                        if probe.fileSize > 0 {
                            LabeledContent("File Size", value: ByteCountFormatter.formatBytes(probe.fileSize))
                        }
                        LabeledContent("Multi-Part Range Support", value: probe.supportsRanges ? "Supported (8x Accelerated)" : "Single-thread stream")
                        if let mime = probe.mimeType {
                            LabeledContent("MIME Type", value: mime)
                        }
                    }
                } else if let error = probeError {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(.orange)
                    }
                }

                Section("File & Category") {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("File Name", text: $customFileName)
                            .shiftNoAutocapitalization()
                            .autocorrectionDisabled()

                        if isDuplicatePresent {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                Text("A file or task with this name already exists.")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                Spacer()
                                Button("Rename") {
                                    suggestUniqueName()
                                }
                                .font(.caption2)
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                            }
                            .padding(.top, 2)
                        }
                    }

                    Picker("Category", selection: $selectedCategory) {
                        ForEach(TaskCategory.allCases) { cat in
                            Label(cat.displayName, systemImage: cat.iconName)
                                .tag(cat)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Connections / Threads")
                            Spacer()
                            Text("\(Int(maxConnections)) threads")
                                .font(.system(.subheadline, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                        }
                        Slider(value: $maxConnections, in: 1...32, step: 1)
                            .tint(.blue)
                    }
                }

                Section {
                    DisclosureGroup("Advanced HTTP Headers", isExpanded: $showAdvancedHeaders) {
                        TextField("Referer URL", text: $referer)
                            .shiftNoAutocapitalization()
                        TextField("Cookie header", text: $cookie)
                            .shiftNoAutocapitalization()
                        TextField("Authorization (Bearer / Basic)", text: $authorization)
                            .shiftNoAutocapitalization()
                        TextField("Custom User-Agent", text: $customUserAgent)
                            .shiftNoAutocapitalization()
                    }
                }
            }
            .navigationTitle("New Download")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        validateAndStartDownload()
                    }
                    .fontWeight(.bold)
                    .disabled(urlString.isEmpty)
                }
            }
            .confirmationDialog(
                "Duplicate File Detected",
                isPresented: $showDuplicateAlert,
                titleVisibility: .visible
            ) {
                Button("Download as Copy (\(suggestedCopyName))") {
                    customFileName = suggestedCopyName
                    executeDownload(replace: false)
                }

                Button("Replace Existing File", role: .destructive) {
                    executeDownload(replace: true)
                }

                Button("Cancel", role: .cancel) {}
            } message: {
                Text("A download or file with the name '\(duplicateFileName)' already exists. Would you like to save it as a new copy or replace the previous file?")
            }
            .onAppear {
                if !urlString.isEmpty {
                    autoPopulateFileName()
                    probeCurrentURL()
                }
            }
        }
    }

    private var suggestedCopyName: String {
        let name = effectiveFileName
        let cat = selectedCategory == .all ? TaskCategory.determineCategory(from: name) : selectedCategory
        return FileStorageService.shared.suggestUniqueFileName(baseName: name, category: cat)
    }

    private func autoPopulateFileName() {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }

        if GoogleDriveURLResolver.isGoogleDriveURL(url) {
            probeCurrentURL()
            return
        }

        guard customFileName.isEmpty || customFileName == "view" || customFileName == "uc", !url.lastPathComponent.isEmpty else { return }
        let rawName = url.lastPathComponent
        if rawName != "view" && rawName != "uc" && rawName != "open" {
            self.customFileName = rawName
            self.selectedCategory = TaskCategory.determineCategory(from: rawName)
        }
    }

    private func suggestUniqueName() {
        self.customFileName = suggestedCopyName
    }

    private func probeCurrentURL() {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            probeError = "Invalid URL format"
            return
        }

        isProbing = true
        probeError = nil

        Task {
            do {
                let meta = try await UniversalURLResolver.resolveURL(
                    url,
                    userAgent: customUserAgent.isEmpty ? nil : customUserAgent
                )
                await MainActor.run {
                    self.probeResult = ChunkedDownloader.ProbeResult(
                        fileSize: meta.fileSize,
                        supportsRanges: meta.supportsRanges,
                        suggestedFileName: meta.fileName,
                        mimeType: meta.mimeType,
                        etag: meta.etag
                    )
                    self.isProbing = false
                    if let name = meta.fileName, !name.isEmpty {
                        self.customFileName = name
                        self.selectedCategory = TaskCategory.determineCategory(from: name, mimeType: meta.mimeType)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isProbing = false
                    self.probeError = error.localizedDescription
                }
            }
        }
    }

    private func validateAndStartDownload() {
        if isDuplicatePresent {
            self.duplicateFileName = effectiveFileName
            self.showDuplicateAlert = true
        } else {
            executeDownload(replace: false)
        }
    }

    private func executeDownload(replace: Bool) {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        HapticManager.triggerNotification(.success)

        var headers: [String: String] = [:]
        if !referer.isEmpty { headers["Referer"] = referer }
        if !cookie.isEmpty { headers["Cookie"] = cookie }
        if !authorization.isEmpty { headers["Authorization"] = authorization }

        let fileName = effectiveFileName
        let cat = selectedCategory == .all ? TaskCategory.determineCategory(from: fileName) : selectedCategory

        if urlString.hasPrefix("magnet:?") {
            if let meta = TorrentMeta.parseMagnetLink(urlString) {
                _ = engine.addTorrentTask(meta: meta, replaceExisting: replace)
            }
        } else if urlString.contains(".m3u8") {
            _ = engine.addHLSTask(url: url, fileName: fileName, headers: headers, replaceExisting: replace)
        } else {
            _ = engine.addDownloadTask(
                url: url,
                fileName: fileName,
                category: cat,
                maxConnections: Int(maxConnections),
                headers: headers,
                userAgent: customUserAgent.isEmpty ? nil : customUserAgent,
                replaceExisting: replace
            )
        }

        dismiss()
    }
}
