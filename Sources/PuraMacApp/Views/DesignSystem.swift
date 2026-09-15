import SwiftUI
import AppKit
import PuraMacCore

/// Every colour here is semantic or derived from the brand ramp, so light and
/// dark mode both come out right without the app ever forcing an appearance.
enum Palette {
    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let pageBackground = Color(nsColor: .underPageBackgroundColor)
    static let hairline = Color(nsColor: .separatorColor)

    /// The ramp the app icon is built from: indigo through blue into cyan.
    static let brandStart = Color(red: 0.41, green: 0.35, blue: 0.96)
    static let brandMid = Color(red: 0.23, green: 0.41, blue: 0.93)
    static let brandEnd = Color(red: 0.08, green: 0.67, blue: 0.91)

    static let brand = LinearGradient(
        colors: [brandStart, brandMid, brandEnd],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static func safety(_ safety: CleanSafety) -> Color {
        switch safety {
        case .safe: return Color(red: 0.13, green: 0.77, blue: 0.51)
        case .review: return Color(red: 0.98, green: 0.63, blue: 0.15)
        case .caution: return Color(red: 0.97, green: 0.35, blue: 0.42)
        }
    }

    static func usage(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.75: return Color(red: 0.13, green: 0.77, blue: 0.51)
        case ..<0.90: return Color(red: 0.98, green: 0.63, blue: 0.15)
        default: return Color(red: 0.97, green: 0.35, blue: 0.42)
        }
    }

    static func ramp(_ color: Color) -> LinearGradient {
        LinearGradient(colors: [color.opacity(0.95), color.opacity(0.62)],
                       startPoint: .top, endPoint: .bottom)
    }
}

/// A frosted panel with a hairline gradient rim and a soft lift, rather than a
/// flat filled rectangle.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: .rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14).strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.28), Color.white.opacity(0.05)],
                        startPoint: .top, endPoint: .bottom),
                    lineWidth: 1))
            .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
    }
}

/// Circular gauge used for the headline storage read-out. Hand-rolled rather
/// than `Gauge` so the track, the gradient sweep and the glow can be tuned.
struct RingGauge<Center: View>: View {
    let progress: Double
    var lineWidth: CGFloat = 16
    var tint: Color = .accentColor
    @ViewBuilder var center: Center

    @State private var animated: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: max(0.001, min(1, animated)))
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.55), tint, tint.opacity(0.85)],
                        center: .center, startAngle: .degrees(0), endAngle: .degrees(360)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.5), radius: 9)

            center
        }
        .onAppear { withAnimation(.spring(duration: 0.9)) { animated = progress } }
        .onChange(of: progress) { _, new in
            withAnimation(.spring(duration: 0.6)) { animated = new }
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let detail: String
    var symbol: String
    var tint: Color = .accentColor
    var progress: Double?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Palette.ramp(tint), in: .rect(cornerRadius: 8))
                        .shadow(color: tint.opacity(0.45), radius: 5, y: 2)
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(value)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if let progress {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule()
                                .fill(Palette.ramp(tint))
                                .frame(width: max(4, geo.size.width * min(1, max(0, progress))))
                                .shadow(color: tint.opacity(0.5), radius: 4)
                        }
                    }
                    .frame(height: 6)
                    .animation(.spring(duration: 0.6), value: progress)
                }

                Text(detail)
                    .font(.caption)
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
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Palette.safety(safety).opacity(0.18), in: .capsule)
            .overlay(Capsule().strokeBorder(Palette.safety(safety).opacity(0.35), lineWidth: 0.5))
            .foregroundStyle(Palette.safety(safety))
            .accessibilityLabel("Safety: \(safety.label)")
    }
}

struct PaneHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            trailing
        }
    }
}

/// Scanning banner with a travelling sheen, so a long scan looks alive rather
/// than hung.
struct ProgressBanner: View {
    let text: String
    let fraction: Double?
    var onCancel: (() -> Void)?

    var body: some View {
        Card(padding: 13) {
            HStack(spacing: 13) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.brand)
                    .symbolEffect(.pulse)

                VStack(alignment: .leading, spacing: 6) {
                    Text(text.isEmpty ? "Working…" : text)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .contentTransition(.opacity)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            if let fraction {
                                Capsule()
                                    .fill(Palette.brand)
                                    .frame(width: max(6, geo.size.width * min(1, max(0, fraction))))
                                    .shadow(color: Palette.brandMid.opacity(0.6), radius: 5)
                            } else {
                                IndeterminateSheen(width: geo.size.width)
                            }
                        }
                    }
                    .frame(height: 6)
                    .animation(.spring(duration: 0.5), value: fraction)
                }

                if let onCancel {
                    Button("Cancel", role: .cancel, action: onCancel)
                        .buttonStyle(.bordered)
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
            let cycle = 1.6
            let phase = (t.truncatingRemainder(dividingBy: cycle)) / cycle
            let barWidth = max(40, width * 0.32)
            let x = -barWidth + (width + barWidth * 2) * phase
            Capsule()
                .fill(Palette.brand)
                .frame(width: barWidth)
                .offset(x: x)
                .opacity(0.9)
        }
        .clipShape(Capsule())
    }
}

struct MessageBanner: View {
    enum Kind { case info, error }
    let kind: Kind
    let text: String
    var onDismiss: (() -> Void)?

    private var tint: Color { kind == .error ? Palette.safety(.caution) : Palette.brandMid }
    private var symbol: String { kind == .error ? "exclamationmark.triangle.fill" : "sparkles" }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Palette.ramp(tint), in: .rect(cornerRadius: 7))

            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(12)
        .background(tint.opacity(0.10), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tint.opacity(0.22), lineWidth: 1))
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Palette.brand)
                .frame(width: 92, height: 92)
                .background(
                    Circle().fill(Palette.brandMid.opacity(0.10))
                        .overlay(Circle().strokeBorder(Palette.brandMid.opacity(0.22), lineWidth: 1)))
                .shadow(color: Palette.brandMid.opacity(0.28), radius: 18, y: 6)

            Text(title).font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 430)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(GlowButtonStyle())
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

/// Prominent action button with the brand ramp and a matching glow.
struct GlowButtonStyle: ButtonStyle {
    var tint: LinearGradient = Palette.brand
    var glow: Color = Palette.brandMid

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(tint, in: .rect(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
            .shadow(color: glow.opacity(configuration.isPressed ? 0.25 : 0.5),
                    radius: configuration.isPressed ? 4 : 10, y: 3)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
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
            Image(systemName: "magnifyingglass")
        }
        .buttonStyle(.borderless)
        .help("Reveal in Finder")
        .accessibilityLabel("Reveal \((path as NSString).lastPathComponent) in Finder")
    }
}

/// Page chrome: a tinted wash behind every pane so panels read as floating.
struct PaneBackground: View {
    var body: some View {
        ZStack {
            Palette.pageBackground
            LinearGradient(
                colors: [Palette.brandStart.opacity(0.12), .clear, Palette.brandEnd.opacity(0.10)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .ignoresSafeArea()
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
}

extension View {
    func paneLayout() -> some View {
        self
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(PaneBackground())
    }

    /// Gradient text for headline figures.
    func brandText() -> some View {
        self.foregroundStyle(Palette.brand)
    }
}
