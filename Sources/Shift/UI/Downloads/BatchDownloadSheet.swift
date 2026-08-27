import SwiftUI

public struct BatchItem: Identifiable {
    public let id = UUID()
    public let url: URL
    public var isSelected: Bool = true
}

public struct BatchDownloadSheet: View {
    @Environment(\.dismiss) private var dismiss
    public let engine: ShiftDownloadEngine

    @State private var patternURL = "https://example.com/episodes/ep_[01-10].mp4"
    @State private var generatedItems: [BatchItem] = []
    @State private var selectedCategory: TaskCategory = .all
    @State private var errorMessage: String?

    public init(engine: ShiftDownloadEngine) {
        self.engine = engine
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Pattern Syntax") {
                    TextField("https://example.com/item_[1-20].jpg", text: $patternURL)
                        .shiftNoAutocapitalization()
                        .autocorrectionDisabled()

                    Text("Use [1-10] for numbers, [01-10] for zero-padded numbers, or [a-z] for letters.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button("Generate URL List") {
                        generateURLs()
                    }
                    .disabled(patternURL.isEmpty)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }

                if !generatedItems.isEmpty {
                    Section("Generated Items (\(generatedItems.filter { $0.isSelected }.count)/\(generatedItems.count) Selected)") {
                        HStack {
                            Button("Select All") {
                                for i in 0..<generatedItems.count { generatedItems[i].isSelected = true }
                            }
                            Spacer()
                            Button("Deselect All") {
                                for i in 0..<generatedItems.count { generatedItems[i].isSelected = false }
                            }
                        }
                        .font(.footnote)

                        ForEach($generatedItems) { $item in
                            HStack {
                                Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(item.isSelected ? .blue : .secondary)
                                    .onTapGesture {
                                        item.isSelected.toggle()
                                    }

                                Text(item.url.lastPathComponent)
                                    .font(.system(.footnote, design: .monospaced))
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Batch Downloader")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add (\(generatedItems.filter { $0.isSelected }.count))") {
                        queueBatch()
                    }
                    .fontWeight(.bold)
                    .disabled(generatedItems.filter { $0.isSelected }.isEmpty)
                }
            }
            .onAppear {
                generateURLs()
            }
        }
    }

    private func generateURLs() {
        errorMessage = nil
        let pattern = patternURL.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let rangeMatch = pattern.range(of: "\\[([^\\]]+)\\]", options: .regularExpression) else {
            errorMessage = "No bracketed range found. E.g. [1-10] or [a-e]"
            return
        }

        let inside = String(pattern[rangeMatch]).replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
        let parts = inside.components(separatedBy: "-")

        guard parts.count == 2 else {
            errorMessage = "Range must be in start-end format, e.g. 1-10 or a-z"
            return
        }

        var results: [BatchItem] = []

        if let startNum = Int(parts[0]), let endNum = Int(parts[1]), startNum <= endNum {
            let isPadded = parts[0].hasPrefix("0") && parts[0].count > 1
            let padLength = parts[0].count

            for num in startNum...endNum {
                let formattedNum: String
                if isPadded {
                    formattedNum = String(format: "%0\(padLength)d", num)
                } else {
                    formattedNum = "\(num)"
                }
                let generatedStr = pattern.replacingCharacters(in: rangeMatch, with: formattedNum)
                if let url = URL(string: generatedStr) {
                    results.append(BatchItem(url: url))
                }
            }
        } else if let startChar = parts[0].first?.asciiValue, let endChar = parts[1].first?.asciiValue, startChar <= endChar {
            for ascii in startChar...endChar {
                let charStr = String(UnicodeScalar(ascii))
                let generatedStr = pattern.replacingCharacters(in: rangeMatch, with: charStr)
                if let url = URL(string: generatedStr) {
                    results.append(BatchItem(url: url))
                }
            }
        } else {
            errorMessage = "Invalid range boundaries"
            return
        }

        self.generatedItems = results
    }

    private func queueBatch() {
        let selected = generatedItems.filter { $0.isSelected }.map { $0.url }
        engine.addBatchTasks(urls: selected, category: selectedCategory == .all ? nil : selectedCategory)
        HapticManager.triggerNotification(.success)
        dismiss()
    }
}
