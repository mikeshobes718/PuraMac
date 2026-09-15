import Foundation
import Observation

/// Independent of macOS's own appearance setting, so the app can be pinned to
/// light or dark regardless of what the rest of the system is doing.
public enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    public var symbol: String {
        switch self {
        case .system: return "circle.righthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon.stars"
        }
    }
}

public enum PreferenceKey {
    public static let autoDiskCheck = "PuraMacAutoDiskCheck"
    public static let notifyOnFinish = "PuraMacNotifyOnFinish"
    public static let lowDiskThreshold = "PuraMacLowDiskThreshold"
    public static let aiModel = "PuraMacAIModel"
    public static let showMenuBarExtra = "PuraMacShowMenuBarExtra"
    public static let largeFileThresholdMB = "PuraMacLargeFileThresholdMB"
    public static let lastLowDiskNotice = "PuraMacLastLowDiskNotice"
    public static let hasCompletedWelcome = "PuraMacHasCompletedWelcome"
    public static let appearance = "PuraMacAppearance"

    public static var defaults: [String: Any] { [
        autoDiskCheck: true,
        notifyOnFinish: true,
        lowDiskThreshold: 0.10,
        showMenuBarExtra: true,
        largeFileThresholdMB: 100,
        aiModel: OpenRouterClient.defaultModel,
        hasCompletedWelcome: false,
        appearance: AppAppearance.system.rawValue
    ] }

    public static func registerDefaults(in store: UserDefaults = .standard) {
        store.register(defaults: defaults)
    }
}

/// Every property here is computed over `UserDefaults` rather than stored, so
/// the store stays the single source of truth. The `@Observable` macro only
/// instruments *stored* properties, which means computed ones register no
/// dependency when read and emit no change when written — SwiftUI would never
/// re-render. `access` / `withMutation` add those hooks by hand, which is what
/// makes a preference change actually reach the UI.
@Observable
@MainActor
public final class Preferences {
    public static let shared = Preferences()

    @ObservationIgnored private let store: UserDefaults

    public init(store: UserDefaults = .standard) {
        self.store = store
        PreferenceKey.registerDefaults(in: store)
    }

    public var autoDiskCheck: Bool {
        get {
            access(keyPath: \.autoDiskCheck)
            return store.bool(forKey: PreferenceKey.autoDiskCheck)
        }
        set {
            guard store.bool(forKey: PreferenceKey.autoDiskCheck) != newValue else { return }
            withMutation(keyPath: \.autoDiskCheck) {
                store.set(newValue, forKey: PreferenceKey.autoDiskCheck)
            }
        }
    }

    public var notifyOnFinish: Bool {
        get {
            access(keyPath: \.notifyOnFinish)
            return store.bool(forKey: PreferenceKey.notifyOnFinish)
        }
        set {
            guard store.bool(forKey: PreferenceKey.notifyOnFinish) != newValue else { return }
            withMutation(keyPath: \.notifyOnFinish) {
                store.set(newValue, forKey: PreferenceKey.notifyOnFinish)
            }
        }
    }

    public var lowDiskThreshold: Double {
        get {
            access(keyPath: \.lowDiskThreshold)
            return store.double(forKey: PreferenceKey.lowDiskThreshold)
        }
        set {
            let clamped = min(0.5, max(0.01, newValue))
            guard store.double(forKey: PreferenceKey.lowDiskThreshold) != clamped else { return }
            withMutation(keyPath: \.lowDiskThreshold) {
                store.set(clamped, forKey: PreferenceKey.lowDiskThreshold)
            }
        }
    }

    public var showMenuBarExtra: Bool {
        get {
            access(keyPath: \.showMenuBarExtra)
            return store.bool(forKey: PreferenceKey.showMenuBarExtra)
        }
        set {
            guard store.bool(forKey: PreferenceKey.showMenuBarExtra) != newValue else { return }
            withMutation(keyPath: \.showMenuBarExtra) {
                store.set(newValue, forKey: PreferenceKey.showMenuBarExtra)
            }
        }
    }

    public var largeFileThresholdMB: Int {
        get {
            access(keyPath: \.largeFileThresholdMB)
            return max(1, store.integer(forKey: PreferenceKey.largeFileThresholdMB))
        }
        set {
            let clamped = max(1, newValue)
            guard store.integer(forKey: PreferenceKey.largeFileThresholdMB) != clamped else { return }
            withMutation(keyPath: \.largeFileThresholdMB) {
                store.set(clamped, forKey: PreferenceKey.largeFileThresholdMB)
            }
        }
    }

    public var aiModel: String {
        get {
            access(keyPath: \.aiModel)
            return store.string(forKey: PreferenceKey.aiModel) ?? OpenRouterClient.defaultModel
        }
        set {
            guard store.string(forKey: PreferenceKey.aiModel) != newValue else { return }
            withMutation(keyPath: \.aiModel) {
                store.set(newValue, forKey: PreferenceKey.aiModel)
            }
        }
    }

    public var hasCompletedWelcome: Bool {
        get {
            access(keyPath: \.hasCompletedWelcome)
            return store.bool(forKey: PreferenceKey.hasCompletedWelcome)
        }
        set {
            guard store.bool(forKey: PreferenceKey.hasCompletedWelcome) != newValue else { return }
            withMutation(keyPath: \.hasCompletedWelcome) {
                store.set(newValue, forKey: PreferenceKey.hasCompletedWelcome)
            }
        }
    }

    public var appearance: AppAppearance {
        get {
            access(keyPath: \.appearance)
            return store.string(forKey: PreferenceKey.appearance)
                .flatMap(AppAppearance.init) ?? .system
        }
        set {
            guard store.string(forKey: PreferenceKey.appearance) != newValue.rawValue else { return }
            withMutation(keyPath: \.appearance) {
                store.set(newValue.rawValue, forKey: PreferenceKey.appearance)
            }
        }
    }
}
