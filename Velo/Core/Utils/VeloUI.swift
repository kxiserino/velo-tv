import SwiftUI

enum VeloUI {
    static let screenHorizontalPadding: CGFloat = 60
    static let screenTopPadding: CGFloat = 28
    static let screenBottomPadding: CGFloat = 56
    static let sectionSpacing: CGFloat = 22
    static let groupSpacing: CGFloat = 10
    static let rowHeight: CGFloat = 68
    static let rowRadius: CGFloat = 14
    static let controlHeight: CGFloat = 56
    static let chipHeight: CGFloat = 38
    static let chipRadius: CGFloat = 19
    static let cardRadius: CGFloat = 14
    static let streamCardWidth: CGFloat = 500
    static let streamCardHeight: CGFloat = 281
    static let streamBadgeHeight: CGFloat = 38
    static let focusAnimation = Animation.easeInOut(duration: 0.14)

    static let surfaceIdleOpacity = 0.07
    static let surfaceFocusedOpacity = 0.16
    static let strokeIdleOpacity = 0.10
    static let strokeFocusedOpacity = 0.44
}

struct VeloBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.12, green: 0.16, blue: 0.18),
                Color(red: 0.10, green: 0.11, blue: 0.12),
                Color.black
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

struct VeloChipLabel: View {
    let title: String
    let systemImage: String
    var isActive = false

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.callout.weight(.semibold))

            Text(title)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(isFocused || isActive ? Color.white : Color.secondary)
        .padding(.horizontal, 14)
        .frame(height: VeloUI.chipHeight)
        .background(
            Capsule()
                .fill(Color.white.opacity(backgroundOpacity))
        )
        .overlay {
            Capsule()
                .strokeBorder(Color.white.opacity(strokeOpacity), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(isFocused ? 0.22 : 0), radius: 10, y: 5)
        .animation(VeloUI.focusAnimation, value: isFocused)
        .animation(VeloUI.focusAnimation, value: isActive)
    }

    private var backgroundOpacity: Double {
        if isFocused { return VeloUI.surfaceFocusedOpacity }
        return isActive ? 0.09 : 0
    }

    private var strokeOpacity: Double {
        if isFocused { return 0.34 }
        return isActive ? 0.20 : 0
    }
}

struct VeloActionButtonLabel: View {
    let title: String
    let systemImage: String
    var isProminent = false
    var tint = Color.white

    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 22)
            .frame(height: VeloUI.controlHeight)
            .background(
                RoundedRectangle(cornerRadius: VeloUI.rowRadius, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay {
                RoundedRectangle(cornerRadius: VeloUI.rowRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(strokeOpacity), lineWidth: isFocused ? 2 : 1)
            }
            .shadow(color: Color.black.opacity(isFocused ? 0.28 : 0), radius: 16, y: 9)
            .opacity(isEnabled ? 1 : 0.46)
            .animation(VeloUI.focusAnimation, value: isFocused)
            .animation(VeloUI.focusAnimation, value: isEnabled)
    }

    private var foregroundColor: Color {
        if !isEnabled { return Color.white.opacity(0.58) }
        return isFocused ? .black : tint
    }

    private var backgroundColor: Color {
        if !isEnabled { return .white.opacity(0.04) }
        if isFocused { return .white.opacity(0.94) }
        return .white.opacity(isProminent ? 0.16 : VeloUI.surfaceIdleOpacity)
    }

    private var strokeOpacity: Double {
        if isFocused { return VeloUI.strokeFocusedOpacity }
        return isProminent ? 0.20 : VeloUI.strokeIdleOpacity
    }
}

struct VeloStatusCard: View {
    let title: String
    let message: String
    let symbol: String

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.white.opacity(0.62))
                .frame(width: 62, height: 62)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: VeloUI.rowRadius, style: .continuous)
                .fill(Color.white.opacity(VeloUI.surfaceIdleOpacity))
        )
        .overlay {
            RoundedRectangle(cornerRadius: VeloUI.rowRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(VeloUI.strokeIdleOpacity), lineWidth: 1)
        }
    }
}
