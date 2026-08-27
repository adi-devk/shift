import SwiftUI

public struct CategoryBadge: View {
    public let category: TaskCategory
    public let showIconOnly: Bool

    public init(category: TaskCategory, showIconOnly: Bool = false) {
        self.category = category
        self.showIconOnly = showIconOnly
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: category.iconName)
                .font(.system(size: 11, weight: .semibold))
            if !showIconOnly {
                Text(category.displayName)
                    .font(.caption2)
                    .fontWeight(.medium)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(category.color.opacity(0.15))
        .foregroundColor(category.color)
        .cornerRadius(6)
    }
}

public struct StatusPill: View {
    public let status: TaskStatus

    public init(status: TaskStatus) {
        self.status = status
    }

    public var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: 6, height: 6)
            Text(status.rawValue)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(status.color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(status.color.opacity(0.12))
        .cornerRadius(4)
    }
}

public struct GlassCard<Content: View>: View {
    public let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding()
            .background(Color.secondaryGroupedBg)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}

public enum HapticManager {
    public enum ImpactStyle {
        case light, medium, heavy
    }
    public enum NotificationType {
        case success, warning, error
    }

    public static func triggerImpact(_ style: ImpactStyle = .medium) {
        #if canImport(UIKit) && os(iOS) && !targetEnvironment(simulator)
        let uiStyle: UIImpactFeedbackGenerator.FeedbackStyle
        switch style {
        case .light: uiStyle = .light
        case .medium: uiStyle = .medium
        case .heavy: uiStyle = .heavy
        }
        let generator = UIImpactFeedbackGenerator(style: uiStyle)
        generator.impactOccurred()
        #endif
    }

    public static func triggerNotification(_ type: NotificationType) {
        #if canImport(UIKit) && os(iOS) && !targetEnvironment(simulator)
        let uiType: UINotificationFeedbackGenerator.FeedbackType
        switch type {
        case .success: uiType = .success
        case .warning: uiType = .warning
        case .error: uiType = .error
        }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(uiType)
        #endif
    }
}
