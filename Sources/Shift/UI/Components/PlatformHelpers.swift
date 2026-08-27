import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum ClipboardHelper {
    public static func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    public static var text: String? {
        #if canImport(UIKit)
        return UIPasteboard.general.string
        #elseif canImport(AppKit)
        return NSPasteboard.general.string(forType: .string)
        #else
        return nil
        #endif
    }
}

public extension Color {
    static var systemGroupedBg: Color {
        #if canImport(UIKit)
        return Color(uiColor: .systemGroupedBackground)
        #elseif canImport(AppKit)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color.secondary
        #endif
    }

    static var secondaryGroupedBg: Color {
        #if canImport(UIKit)
        return Color(uiColor: .secondarySystemGroupedBackground)
        #elseif canImport(AppKit)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color.gray.opacity(0.1)
        #endif
    }

    static var tertiarySystemFillColor: Color {
        #if canImport(UIKit)
        return Color(uiColor: .tertiarySystemFill)
        #else
        return Color.gray.opacity(0.15)
        #endif
    }

    static var systemFillColor: Color {
        #if canImport(UIKit)
        return Color(uiColor: .systemFill)
        #else
        return Color.gray.opacity(0.2)
        #endif
    }
}

public extension View {
    @ViewBuilder
    func shiftListStyle() -> some View {
        #if os(iOS)
        self.listStyle(.insetGrouped)
        #else
        self.listStyle(.inset)
        #endif
    }

    @ViewBuilder
    func shiftNoAutocapitalization() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never)
        #else
        self
        #endif
    }

    @ViewBuilder
    func shiftInlineTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

#if canImport(UIKit)
public struct ShareSheet: UIViewControllerRepresentable {
    public let activityItems: [Any]

    public init(activityItems: [Any]) {
        self.activityItems = activityItems
    }

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
