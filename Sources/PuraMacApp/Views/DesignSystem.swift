import SwiftUI
import AppKit
import PuraMacCore

/// Flat, neutral surfaces with hairline separation — the current desktop-app
/// idiom. Colour is reserved for state that actually means something (safety,
/// capacity, the primary action); everything else stays greyscale so the data
/// reads first.
enum Palette {
    static let pageBackground = Color(nsColor: .windowBackgroundColor)
    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let hairline = Color.primary.opacity(0.10)

    static let accent = Color.accentColor

    /// Retained so existing call sites keep compiling. The UI now leans on
    /// `accent` plus greyscale rather than a three-stop brand gradient.
    static let brandStart = Color.accentColor
    static let brandMid = Color.accentColor
    static let brandEnd = Color.accentColor
    static let brand = LinearGradient(colors: [Color.accentColor, Color.accentColor],
                                      startPoint: .leading, endPoint: .trailing)

    static func safety(_ safety: CleanSafety) -> Color {
        switch safety {
        case .safe: return Color(red: 0.20, green: 0.72, blue: 0.47)
        case .review: return Color(red: 0.90, green: 0.62, blue: 0.20)
        case .caution: return Color(red: 0.90, green: 0.38, blue: 0.38)
        }
    }

    static func usage(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.75: return Color(red: 0.20, green: 0.72, blue: 0.47)
        case ..<0.90: return Color(red: 0.90, green: 0.62, blue: 0.20)
        default: return Color(red: 0.90, green: 0.38, blue: 0.38)
        }
    }

    static func ramp(_ color: Color) -> LinearGradient {
        LinearGradient(colors: [color, color], startPoint: .top, endPoint: .bottom)
    }
}

/// A plain surface with a hairline edge. No shadow, no gradient rim — those
/// read as depth for depth's sake and are what date an interface fastest.
struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.cardBackground, in: .rect(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Palette.hairline, lineWidth: 1))
    }
}

/// Thin capacity ring. One colour, no glow — it is a read-out, not an ornament.
struct RingGauge<Center: View>: View {
    let progress: Double
    var lineWidth: CGFloat = 8
    var tint: Color = .accentColor
    @ViewBuilder var center: Center

    @State private var animated: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.09), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, animated)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center
        }
        .onAppear { withAnimation(.easeOut(duration: 0.5)) { animated = progress } }
        .onChange(of: progress) { _, new in
            withAnimation(.easeOut(duration: 0.35)) { animated = new }
        }
    }
}

/// Muted label, large plain figure, optional thin meter. The number carries the
/// emphasis instead of a coloured chip competing with it.
struct StatTile: View {
    let title: String
    let value: String
    let detail: String
    var symbol: String
    var tint: Color = .accentColor
    var progress: Double?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Text(value)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if let progress {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.09))
                            Capsule()
                                .fill(tint)
                                .frame(width: max(3, geo.size.width * min(1, max(0, progress))))
                        }
                    }
                    .frame(height: 4)
                    .animation(.easeOut(duration: 0.35), value: progress)
                }

                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value). \(detail)")
    }
}

struct SafetyBadge: View {
    let safety: CleanSafety

    var body: some View {
        Text(safety.label)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(Palette.safety(safety))
            .background(Palette.safety(safety).opacity(0.12), in: .rect(cornerRadius: 4))
            .accessibilityLabel("Safety: \(safety.label)")
    }
}

struct PaneHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 22, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            trailing
        }
    }
}

struct ProgressBanner: View {
    let text: String
    let fraction: Double?
    var onCancel: (() -> Void)?

    var body: some View {
        Card(padding: 12) {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)

                VStack(alignment: .leading, spacing: 6) {
                    Text(text.isEmpty ? "Working…" : text)
                        .font(.system(size: 12))
                        .lineLimit(1)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.09))
                            if let fraction {
                                Capsule()
                                    .fill(Palette.accent)
                                    .frame(width: max(3, geo.size.width * min(1, max(0, fraction))))
                            } else {
                                IndeterminateSheen(width: geo.size.width)
                            }
                        }
                    }
                    .frame(height: 4)
                    .animation(.easeOut(duration: 0.3), value: fraction)
                }

                if let onCancel {
                    Button("Cancel", role: .cancel, action: onCancel)
                        .controlSize(.small)
                }
            }
        }
    }
}

private struct IndeterminateSheen: View {
    let width: CGFloat

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let cycle = 1.4
            let phase = (t.truncatingRemainder(dividingBy: cycle)) / cycle
            let barWidth = max(36, width * 0.28)
            Capsule()
                .fill(Palette.accent)
                .frame(width: barWidth)
                .offset(x: -barWidth + (width + barWidth * 2) * phase)
        }
        .clipShape(Capsule())
    }
}

struct MessageBanner: View {
    enum Kind { case info, error }
    let kind: Kind
    let text: String
    var onDismiss: (() -> Void)?

    private var tint: Color { kind == .error ? Palette.safety(.caution) : Palette.accent }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: kind == .error ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(tint)
                .padding(.top, 1)

            Text(text)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(11)
        .background(tint.opacity(0.08), in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tint.opacity(0.18), lineWidth: 1))
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)

            Text(title).font(.system(size: 14, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(GlowButtonStyle())
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

/// Primary action. Flat accent fill — the coloured glow this used to carry is
/// exactly the kind of decoration that dates an interface. Name kept so the
/// existing call sites keep compiling.
struct GlowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .padding(.vertical, 6)
            .background(Palette.accent.opacity(configuration.isPressed ? 0.75 : 1),
                        in: .rect(cornerRadius: 7))
    }
}

/// Reveals a path in Finder. Used everywhere a file is listed, so the user can
/// always go look before agreeing to remove anything.
struct RevealButton: View {
    let path: String

    var body: some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } label: {
            Image(systemName: "arrow.up.forward.square")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Reveal in Finder")
        .accessibilityLabel("Reveal \((path as NSString).lastPathComponent) in Finder")
    }
}

/// Flat page ground. The previous tinted gradient wash bled a muddy band down
/// the edge of the detail pane, which is what made the split look misaligned.
struct PaneBackground: View {
    var body: some View {
        Palette.pageBackground.ignoresSafeArea()
    }
}

extension AppAppearance {
    /// `nil` means "no override" — SwiftUI then falls through to the system
    /// setting, which is exactly what `.system` should mean.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Applying the appearance override.
///
/// This must never run as a side effect of a view *update*: assigning
/// `NSApplication.appearance` triggers a re-render, and doing that from inside
/// `updateNSView` re-enters the update, which assigns again — SwiftUI recurses
/// until the stack overflows. It is driven from `onChange` instead, which fires
/// only on a real change, and the assignment is guarded so a redundant write
/// can never restart the cycle.
enum AppearanceController {
    @MainActor
    static func apply(_ scheme: ColorScheme?) {
        let appearance: NSAppearance?
        switch scheme {
        case .light: appearance = NSAppearance(named: .aqua)
        case .dark: appearance = NSAppearance(named: .darkAqua)
        case nil: appearance = nil
        case .some: appearance = nil
        }
        guard NSApplication.shared.appearance?.name != appearance?.name else { return }
        NSApplication.shared.appearance = appearance
    }
}

extension View {
    /// Forces the whole app — window chrome and AppKit-backed controls
    /// included — to a specific appearance, or back to following the system
    /// when `scheme` is `nil`.
    func forceWindowAppearance(_ scheme: ColorScheme?) -> some View {
        self
            .onAppear { AppearanceController.apply(scheme) }
            .onChange(of: scheme) { _, updated in AppearanceController.apply(updated) }
            .preferredColorScheme(scheme)
    }

    func paneLayout() -> some View {
        self
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(PaneBackground())
    }

    func brandText() -> some View {
        self.foregroundStyle(Palette.accent)
    }
}
