import CoreGraphics
import Foundation

struct MacInputSystemProfile: Equatable {
    var naturalScroll = true
    var momentumScroll = true
    var secondaryClick = true
    var tapToClick = false
    var pinchGesture = true
    var swipeGesture = true
    var threeFingerDrag = false
    var hapticsEnabled = true
    var trackpadScaling = 0.875
    var mouseScaling = 1.0
    var keyRepeat = 5
    var initialKeyRepeat = 15

    var preferredPointerScaling: Double {
        if trackpadScaling > 0 {
            return trackpadScaling
        }
        if mouseScaling > 0 {
            return mouseScaling
        }
        return 1.0
    }
}

struct InputRoutingPreferences: Equatable {
    var followSystemSettings = true
    var manualPointerGain = 2.2
    var manualScrollGain = 1.0
    var manualPinchGain = 1.0
    var manualSwipeEnabled = true
    var manualPinchEnabled = true
    var manualHapticsEnabled = true
}

struct ControlInputTuningProfile: Equatable {
    var pointerGain: CGFloat
    var scrollGain: Double
    var pinchGain: Double
    var swipeEnabled: Bool
    var pinchEnabled: Bool
    var hapticsEnabled: Bool
    var momentumScrollEnabled: Bool
    var naturalScrollEnabled: Bool
    var keyRepeat: Int
    var initialKeyRepeat: Int

    static let standard = ControlInputTuningProfile(
        pointerGain: 2.2,
        scrollGain: 1.12,
        pinchGain: 1.0,
        swipeEnabled: true,
        pinchEnabled: true,
        hapticsEnabled: true,
        momentumScrollEnabled: true,
        naturalScrollEnabled: true,
        keyRepeat: 5,
        initialKeyRepeat: 15
    )
}

enum MacInputSettingsResolver {
    static func resolve(
        systemProfile: MacInputSystemProfile,
        preferences: InputRoutingPreferences
    ) -> ControlInputTuningProfile {
        if preferences.followSystemSettings {
            let scale = systemProfile.preferredPointerScaling
            let pointerGain = CGFloat(clamp(1.35 + (scale * 0.95), to: 1.2...3.6))
            let momentumBoost = systemProfile.momentumScroll ? 1.18 : 1.0
            let scrollGain = (1.0 + (scale * 0.12)) * momentumBoost
            return ControlInputTuningProfile(
                pointerGain: pointerGain,
                scrollGain: clamp(scrollGain, to: 0.75...2.2),
                pinchGain: 1.0,
                swipeEnabled: systemProfile.swipeGesture,
                pinchEnabled: systemProfile.pinchGesture,
                hapticsEnabled: systemProfile.hapticsEnabled,
                momentumScrollEnabled: systemProfile.momentumScroll,
                naturalScrollEnabled: systemProfile.naturalScroll,
                keyRepeat: systemProfile.keyRepeat,
                initialKeyRepeat: systemProfile.initialKeyRepeat
            )
        }

        return ControlInputTuningProfile(
            pointerGain: CGFloat(clamp(preferences.manualPointerGain, to: 1.0...4.0)),
            scrollGain: clamp(preferences.manualScrollGain, to: 0.4...2.5),
            pinchGain: clamp(preferences.manualPinchGain, to: 0.4...2.5),
            swipeEnabled: preferences.manualSwipeEnabled,
            pinchEnabled: preferences.manualPinchEnabled,
            hapticsEnabled: preferences.manualHapticsEnabled,
            momentumScrollEnabled: systemProfile.momentumScroll,
            naturalScrollEnabled: systemProfile.naturalScroll,
            keyRepeat: systemProfile.keyRepeat,
            initialKeyRepeat: systemProfile.initialKeyRepeat
        )
    }
}

final class InputRoutingPreferencesStore {
    private enum Keys {
        static let followSystemSettings = "com.mtog.input.follow-system-settings"
        static let manualPointerGain = "com.mtog.input.manual-pointer-gain"
        static let manualScrollGain = "com.mtog.input.manual-scroll-gain"
        static let manualPinchGain = "com.mtog.input.manual-pinch-gain"
        static let manualSwipeEnabled = "com.mtog.input.manual-swipe-enabled"
        static let manualPinchEnabled = "com.mtog.input.manual-pinch-enabled"
        static let manualHapticsEnabled = "com.mtog.input.manual-haptics-enabled"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> InputRoutingPreferences {
        InputRoutingPreferences(
            followSystemSettings: bool(forKey: Keys.followSystemSettings, defaultValue: true),
            manualPointerGain: double(forKey: Keys.manualPointerGain, defaultValue: 2.2),
            manualScrollGain: double(forKey: Keys.manualScrollGain, defaultValue: 1.0),
            manualPinchGain: double(forKey: Keys.manualPinchGain, defaultValue: 1.0),
            manualSwipeEnabled: bool(forKey: Keys.manualSwipeEnabled, defaultValue: true),
            manualPinchEnabled: bool(forKey: Keys.manualPinchEnabled, defaultValue: true),
            manualHapticsEnabled: bool(forKey: Keys.manualHapticsEnabled, defaultValue: true)
        )
    }

    func save(_ preferences: InputRoutingPreferences) {
        defaults.set(preferences.followSystemSettings, forKey: Keys.followSystemSettings)
        defaults.set(preferences.manualPointerGain, forKey: Keys.manualPointerGain)
        defaults.set(preferences.manualScrollGain, forKey: Keys.manualScrollGain)
        defaults.set(preferences.manualPinchGain, forKey: Keys.manualPinchGain)
        defaults.set(preferences.manualSwipeEnabled, forKey: Keys.manualSwipeEnabled)
        defaults.set(preferences.manualPinchEnabled, forKey: Keys.manualPinchEnabled)
        defaults.set(preferences.manualHapticsEnabled, forKey: Keys.manualHapticsEnabled)
    }

    private func bool(forKey key: String, defaultValue: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }

    private func double(forKey key: String, defaultValue: Double) -> Double {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.double(forKey: key)
    }
}

final class MacInputSystemProfileReader {
    private let globalDefaults: UserDefaults
    private let builtInTrackpadDefaults: UserDefaults?
    private let bluetoothTrackpadDefaults: UserDefaults?

    init(globalDefaults: UserDefaults = .standard) {
        self.globalDefaults = globalDefaults
        self.builtInTrackpadDefaults = UserDefaults(suiteName: "com.apple.AppleMultitouchTrackpad")
        self.bluetoothTrackpadDefaults = UserDefaults(suiteName: "com.apple.driver.AppleBluetoothMultitouch.trackpad")
    }

    func read() -> MacInputSystemProfile {
        MacInputSystemProfile(
            naturalScroll: bool(
                globalDefaults.object(forKey: "com.apple.swipescrolldirection"),
                defaultValue: true
            ),
            momentumScroll: bool(
                globalDefaults.object(forKey: "com.apple.trackpad.momentumScroll")
                    ?? trackpadObject(forKey: "TrackpadMomentumScroll"),
                defaultValue: true
            ),
            secondaryClick: bool(
                globalDefaults.object(forKey: "com.apple.trackpad.enableSecondaryClick")
                    ?? trackpadObject(forKey: "TrackpadRightClick"),
                defaultValue: true
            ),
            tapToClick: bool(
                trackpadObject(forKey: "Clicking"),
                defaultValue: false
            ),
            pinchGesture: bool(
                globalDefaults.object(forKey: "com.apple.trackpad.pinchGesture")
                    ?? trackpadObject(forKey: "TrackpadPinch"),
                defaultValue: true
            ),
            swipeGesture: gestureEnabled(
                globalDefaults.object(forKey: "com.apple.trackpad.threeFingerHorizSwipeGesture")
                    ?? trackpadObject(forKey: "TrackpadThreeFingerHorizSwipeGesture"),
                fallback: true
            ) || gestureEnabled(
                globalDefaults.object(forKey: "com.apple.trackpad.fourFingerHorizSwipeGesture")
                    ?? trackpadObject(forKey: "TrackpadFourFingerHorizSwipeGesture"),
                fallback: true
            ),
            threeFingerDrag: bool(
                globalDefaults.object(forKey: "com.apple.trackpad.threeFingerDragGesture")
                    ?? trackpadObject(forKey: "TrackpadThreeFingerDrag"),
                defaultValue: false
            ),
            hapticsEnabled: bool(
                trackpadObject(forKey: "ActuateDetents"),
                defaultValue: true
            ) && !bool(
                trackpadObject(forKey: "ForceSuppressed"),
                defaultValue: false
            ),
            trackpadScaling: double(
                globalDefaults.object(forKey: "com.apple.trackpad.scaling"),
                defaultValue: 0.875
            ),
            mouseScaling: double(
                globalDefaults.object(forKey: "com.apple.mouse.scaling"),
                defaultValue: 1.0
            ),
            keyRepeat: int(
                globalDefaults.object(forKey: "KeyRepeat"),
                defaultValue: 5
            ),
            initialKeyRepeat: int(
                globalDefaults.object(forKey: "InitialKeyRepeat"),
                defaultValue: 15
            )
        )
    }

    private func trackpadObject(forKey key: String) -> Any? {
        builtInTrackpadDefaults?.object(forKey: key)
            ?? bluetoothTrackpadDefaults?.object(forKey: key)
    }

    private func bool(_ value: Any?, defaultValue: Bool) -> Bool {
        switch value {
        case let value as NSNumber:
            return value.boolValue
        case let value as Bool:
            return value
        default:
            return defaultValue
        }
    }

    private func int(_ value: Any?, defaultValue: Int) -> Int {
        switch value {
        case let value as NSNumber:
            return value.intValue
        case let value as Int:
            return value
        default:
            return defaultValue
        }
    }

    private func double(_ value: Any?, defaultValue: Double) -> Double {
        switch value {
        case let value as NSNumber:
            return value.doubleValue
        case let value as Double:
            return value
        default:
            return defaultValue
        }
    }

    private func gestureEnabled(_ value: Any?, fallback: Bool) -> Bool {
        let raw = int(value, defaultValue: fallback ? 2 : 0)
        return raw != 0
    }
}

private func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
    min(max(value, range.lowerBound), range.upperBound)
}
