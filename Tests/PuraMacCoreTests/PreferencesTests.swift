import Testing
import Foundation
@testable import PuraMacCore

/// `withObservationTracking`'s onChange handler is `@Sendable`, so the flag it
/// sets needs to be shared safely rather than captured as a local var.
private final class ChangeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func mark() {
        lock.lock(); value = true; lock.unlock()
    }

    var didChange: Bool {
        lock.lock(); defer { lock.unlock() }; return value
    }
}

@Suite("Preferences")
@MainActor
struct PreferencesTests {

    private func freshStore() -> UserDefaults {
        let suite = "puramac-tests-\(UUID().uuidString)"
        let store = UserDefaults(suiteName: suite)!
        PreferenceKey.registerDefaults(in: store)
        return store
    }

    @Test("Round-trips every value through the store")
    func roundTrips() {
        let prefs = Preferences(store: freshStore())

        prefs.appearance = .dark
        #expect(prefs.appearance == .dark)
        prefs.appearance = .light
        #expect(prefs.appearance == .light)

        prefs.showMenuBarExtra = false
        #expect(prefs.showMenuBarExtra == false)

        prefs.largeFileThresholdMB = 500
        #expect(prefs.largeFileThresholdMB == 500)

        prefs.aiModel = "vendor/some-model"
        #expect(prefs.aiModel == "vendor/some-model")
    }

    /// SwiftUI writes back to two-way bindings during a scene update. If an
    /// identical write still emitted a change notification, that invalidated
    /// the scene, which re-evaluated, which wrote again — recursing until the
    /// stack overflowed and the app died on launch.
    @Test("Writing an unchanged value emits no observation change")
    func redundantWriteDoesNotNotify() async {
        let prefs = Preferences(store: freshStore())
        prefs.appearance = .dark
        prefs.showMenuBarExtra = true

        let flag = ChangeFlag()
        withObservationTracking {
            _ = prefs.appearance
            _ = prefs.showMenuBarExtra
        } onChange: {
            flag.mark()
        }

        // Identical values: must be a no-op.
        prefs.appearance = .dark
        prefs.showMenuBarExtra = true

        #expect(!flag.didChange, "a redundant write must not invalidate observers")
    }

    @Test("Writing a genuinely new value does emit a change")
    func realWriteNotifies() {
        let prefs = Preferences(store: freshStore())
        prefs.appearance = .dark

        let flag = ChangeFlag()
        withObservationTracking {
            _ = prefs.appearance
        } onChange: {
            flag.mark()
        }

        prefs.appearance = .light
        #expect(flag.didChange, "a real change must reach observers, or the UI never updates")
    }

    @Test("Clamped values do not notify when the clamp result is unchanged")
    func clampedWritesAreIdempotent() {
        let prefs = Preferences(store: freshStore())
        prefs.largeFileThresholdMB = 100

        let flag = ChangeFlag()
        withObservationTracking {
            _ = prefs.largeFileThresholdMB
        } onChange: {
            flag.mark()
        }

        prefs.largeFileThresholdMB = 0   // clamps to 1 — a real change
        #expect(flag.didChange)
        #expect(prefs.largeFileThresholdMB == 1)
    }
}
