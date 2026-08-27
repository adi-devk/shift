import SwiftUI

public struct ChangeURLSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var engine: ShiftDownloadEngine
    public let taskId: UUID

    @State private var newURLString: String = ""
    @State private var errorMessage: String? = nil

    public init(engine: ShiftDownloadEngine, taskId: UUID, currentURL: String = "") {
        self.engine = engine
        self.taskId = taskId
        _newURLString = State(initialValue: currentURL)
    }

    private var task: DownloadTask? {
        engine.tasks.first(where: { $0.id == taskId })
    }

    private var isValidURL: Bool {
        let trimmed = newURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https" || scheme == "magnet") && url.host != nil
    }

    public var body: some View {
        NavigationStack {
            Form {
                if let task = task {
                    // Task Summary Card
                    Section {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(task.category.color.opacity(0.15))
                                    .frame(width: 44, height: 44)
                                Image(systemName: task.category.iconName)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(task.category.color)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(task.fileName)
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .lineLimit(1)

                                Text("\(task.formattedDownloadedSize) of \(task.formattedTotalSize) (\(Int(task.progress * 100))%)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    Section(
                        header: Text("Refresh Expired Link"),
                        footer: Text("If the link has expired (e.g. temporary cloud links, signed URLs), enter the new URL. The download will resume from where it left off without starting over.")
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("New Download URL")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button {
                                    if let paste = ClipboardHelper.text, !paste.isEmpty {
                                        newURLString = paste.trimmingCharacters(in: .whitespacesAndNewlines)
                                        HapticManager.triggerImpact(.light)
                                    }
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: "doc.on.clipboard")
                                        Text("Paste")
                                    }
                                    .font(.caption2)
                                }
                                .buttonStyle(.bordered)
                                .tint(.blue)
                            }

                            TextField("https://...", text: $newURLString, axis: .vertical)
                                .lineLimit(3...6)
                                .shiftNoAutocapitalization()
                                .autocorrectionDisabled()
                                .font(.system(.footnote, design: .monospaced))
                        }
                        .padding(.vertical, 4)

                        if let err = errorMessage {
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }

                    Section {
                        Button {
                            applyURLChange(resume: true)
                        } label: {
                            HStack {
                                Spacer()
                                Image(systemName: "arrow.clockwise.circle.fill")
                                    .font(.system(size: 16, weight: .bold))
                                Text("Update URL & Resume")
                                    .fontWeight(.bold)
                                Spacer()
                            }
                        }
                        .disabled(!isValidURL)
                        .tint(.blue)

                        Button {
                            applyURLChange(resume: false)
                        } label: {
                            HStack {
                                Spacer()
                                Text("Update URL Only")
                                Spacer()
                            }
                        }
                        .disabled(!isValidURL)
                        .foregroundColor(.primary)
                    }
                }
            }
            .navigationTitle("Change Download URL")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func applyURLChange(resume: Bool) {
        let trimmed = newURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            errorMessage = "Invalid URL format"
            return
        }

        HapticManager.triggerImpact(.medium)
        engine.updateTaskURL(id: taskId, newURL: url, resumeImmediately: resume)
        dismiss()
    }
}
