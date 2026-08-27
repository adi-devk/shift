import SwiftUI

public struct BrowserTabOverviewView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject public var tabManager: BrowserTabManager
    public let onSelectTab: (UUID) -> Void
    public let onNewTab: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    public init(
        tabManager: BrowserTabManager,
        onSelectTab: @escaping (UUID) -> Void,
        onNewTab: @escaping () -> Void
    ) {
        self.tabManager = tabManager
        self.onSelectTab = onSelectTab
        self.onNewTab = onNewTab
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(tabManager.currentTabs) { tab in
                            TabCardView(
                                tab: tab,
                                isSelected: tab.id == tabManager.currentActiveTabId,
                                isPrivate: tabManager.isPrivateMode,
                                onSelect: {
                                    HapticManager.triggerImpact(.light)
                                    onSelectTab(tab.id)
                                    dismiss()
                                },
                                onClose: {
                                    HapticManager.triggerImpact(.medium)
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        tabManager.closeTab(id: tab.id)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 80)
                }

                // Safari Bottom Bar
                VStack(spacing: 0) {
                    Divider()
                    HStack {
                        // Private Browsing Toggle Button
                        Button {
                            HapticManager.triggerImpact(.medium)
                            withAnimation(.spring()) {
                                tabManager.isPrivateMode.toggle()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: tabManager.isPrivateMode ? "lock.shield.fill" : "lock.shield")
                                Text("Private")
                            }
                            .font(.subheadline)
                            .fontWeight(tabManager.isPrivateMode ? .bold : .medium)
                            .foregroundColor(tabManager.isPrivateMode ? .purple : .blue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(tabManager.isPrivateMode ? Color.purple.opacity(0.15) : Color.clear)
                            .clipShape(Capsule())
                        }

                        Spacer()

                        // Tabs Count
                        Text("\(tabManager.currentTabs.count) \(tabManager.isPrivateMode ? "Private " : "")\(tabManager.currentTabs.count == 1 ? "Tab" : "Tabs")")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)

                        Spacer()

                        // New Tab Button (+)
                        Button {
                            HapticManager.triggerImpact(.medium)
                            onNewTab()
                            dismiss()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .semibold))
                                .frame(width: 36, height: 36)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                }
            }
            .background(tabManager.isPrivateMode ? Color.black.opacity(0.92) : Color.secondaryGroupedBg)
            .navigationTitle(tabManager.isPrivateMode ? "Private Browsing" : "Tabs")
            .shiftInlineTitle()
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    if !tabManager.currentTabs.isEmpty {
                        Button("Close All") {
                            HapticManager.triggerNotification(.warning)
                            withAnimation {
                                tabManager.closeAllTabs()
                            }
                        }
                        .foregroundColor(.red)
                    }
                }
                #else
                ToolbarItem(placement: .navigation) {
                    if !tabManager.currentTabs.isEmpty {
                        Button("Close All") {
                            tabManager.closeAllTabs()
                        }
                        .foregroundColor(.red)
                    }
                }
                #endif

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Tab Preview Card
struct TabCardView: View {
    let tab: BrowserTab
    let isSelected: Bool
    let isPrivate: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 0) {
                // Card Header
                HStack(spacing: 6) {
                    Image(systemName: isPrivate ? "lock.shield.fill" : "globe")
                        .font(.system(size: 11))
                        .foregroundColor(isPrivate ? .purple : .blue)

                    Text(tab.displayTitle)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    // Close Button
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(6)
                            .background(Color.tertiarySystemFillColor)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(isPrivate ? Color.gray.opacity(0.25) : Color.tertiarySystemFillColor)

                Divider()

                // Card Thumbnail / Content Area
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: isPrivate ? "lock.fill" : "safari")
                        .font(.system(size: 28))
                        .foregroundColor(isPrivate ? .purple.opacity(0.6) : .blue.opacity(0.4))

                    Text(tab.hostDomain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .background(isPrivate ? Color.black.opacity(0.4) : Color.secondaryGroupedBg)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? (isPrivate ? Color.purple : Color.blue) : Color.secondary.opacity(0.25), lineWidth: isSelected ? 2.5 : 0.8)
            )
            .shadow(color: Color.black.opacity(isSelected ? 0.15 : 0.05), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }
}
