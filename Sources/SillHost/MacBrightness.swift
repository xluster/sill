import CoreGraphics
import Foundation

/// The brightness of this Mac's built-in display, through DisplayServices, and of its keyboard's
/// backlight, through CoreBrightness's KeyboardBrightnessClient (private frameworks macOS's own
/// brightness keys use; looked up at run time, so a Mac without them just says so). Night mode
/// (kind 36): the lowest brightness that still lights the display, so ScreenCaptureKit keeps
/// capturing, and the keyboard's backlight off with its automatic brightness, each put back after.
/// External displays and keyboards are left as they are.
enum MacBrightness {
    private typealias Get = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Set = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let library = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let get: Get? = library.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: Get.self) }
    private static let set: Set? = library.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: Set.self) }

    /// What each built-in display was at before night mode; nil while it is off. Kept in the
    /// defaults too, so a Sill relaunched in night mode still puts it back.
    @MainActor private static var saved: [CGDirectDisplayID: Float]? {
        get {
            (UserDefaults.standard.dictionary(forKey: "nightDisplays") as? [String: Double])
                .map { Dictionary(uniqueKeysWithValues: $0.compactMap { k, v in UInt32(k).map { ($0, Float(v)) } }) }
        }
        set {
            if let newValue {
                UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: newValue.map { (String($0.key), Double($0.value)) }),
                                          forKey: "nightDisplays")
            } else {
                UserDefaults.standard.removeObject(forKey: "nightDisplays")
            }
        }
    }

    /// Night mode's brightness: 0, the display's backlight off (Alexis, 2026-10-25: the lowest level
    /// that still lit it was too bright in a dark room). macOS does not count the display as asleep,
    /// so ScreenCaptureKit keeps capturing and the device keeps its picture.
    private static let night: Float = 0

    /// The keyboard backlights: their brightness and whether macOS sets it from the room's light,
    /// before night mode; nil while it is off.
    @MainActor private static var savedKeyboards: [UInt64: (level: Float, auto: Bool)]? {
        get {
            (UserDefaults.standard.dictionary(forKey: "nightKeyboards") as? [String: [Double]]).map {
                Dictionary(uniqueKeysWithValues: $0.compactMap { k, v in
                    UInt64(k).flatMap { id in v.count == 2 ? (id, (Float(v[0]), v[1] != 0)) : nil }
                })
            }
        }
        set {
            if let newValue {
                UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: newValue.map {
                    (String($0.key), [Double($0.value.level), $0.value.auto ? 1 : 0])
                }), forKey: "nightKeyboards")
            } else {
                UserDefaults.standard.removeObject(forKey: "nightKeyboards")
            }
        }
    }

    private typealias KeyboardGet = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias KeyboardSet = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
    private typealias KeyboardAutoGet = @convention(c) (AnyObject, Selector, UInt64) -> Bool
    private typealias KeyboardAutoSet = @convention(c) (AnyObject, Selector, Bool, UInt64) -> Void

    private static let keyboards: NSObject? = {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY) != nil,
              let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return nil }
        let client = type.init()
        let needed = ["copyKeyboardBacklightIDs", "brightnessForKeyboard:", "setBrightness:forKeyboard:",
                      "isAutoBrightnessEnabledForKeyboard:", "enableAutoBrightness:forKeyboard:"]
        return needed.allSatisfy { client.responds(to: Selector($0)) } ? client : nil
    }()

    private static func keyboardIDs(_ client: NSObject) -> [UInt64] {
        (client.perform(Selector(("copyKeyboardBacklightIDs")))?.takeRetainedValue() as? [NSNumber] ?? []).map(\.uint64Value)
    }

    /// The keyboard backlights off (their level and automatic brightness kept), or put back. A line,
    /// or nil when this Mac has none to dim.
    @MainActor private static func setKeyboards(_ on: Bool) -> String? {
        guard let client = keyboards else { return nil }
        let get = unsafeBitCast(client.method(for: Selector(("brightnessForKeyboard:"))), to: KeyboardGet.self)
        let set = unsafeBitCast(client.method(for: Selector(("setBrightness:forKeyboard:"))), to: KeyboardSet.self)
        let autoGet = unsafeBitCast(client.method(for: Selector(("isAutoBrightnessEnabledForKeyboard:"))), to: KeyboardAutoGet.self)
        let autoSet = unsafeBitCast(client.method(for: Selector(("enableAutoBrightness:forKeyboard:"))), to: KeyboardAutoSet.self)
        if on {
            let ids = keyboardIDs(client)
            guard !ids.isEmpty else { return nil }
            if savedKeyboards == nil {
                var kept: [UInt64: (level: Float, auto: Bool)] = [:]
                for id in ids {
                    kept[id] = (get(client, Selector(("brightnessForKeyboard:")), id),
                                autoGet(client, Selector(("isAutoBrightnessEnabledForKeyboard:")), id))
                }
                savedKeyboards = kept
            }
            for id in ids {
                // Off with its automatic brightness, or the room's light would turn it back on.
                autoSet(client, Selector(("enableAutoBrightness:forKeyboard:")), false, id)
                _ = set(client, Selector(("setBrightness:forKeyboard:")), 0, id)
            }
            return "the keyboard's backlight off"
        } else {
            guard let kept = savedKeyboards else { return nil }
            for (id, was) in kept {
                _ = set(client, Selector(("setBrightness:forKeyboard:")), was.level, id)
                if was.auto { autoSet(client, Selector(("enableAutoBrightness:forKeyboard:")), true, id) }
            }
            savedKeyboards = nil
            return "the keyboard's backlight put back"
        }
    }

    /// The built-in displays online now.
    private static func builtIn() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) != 0 }
    }

    /// Night mode on or off; a line saying what was done.
    @MainActor static func setNight(_ on: Bool) -> String {
        let keyboard = setKeyboards(on).map { ", " + $0 } ?? ""
        guard let get, let set else { return "Night mode: this Mac has no DisplayServices; brightness left as it is\(keyboard)." }
        let displays = builtIn()
        guard !displays.isEmpty else { return "Night mode: no built-in display; brightness left as it is\(keyboard)." }
        if on {
            if saved == nil {
                var levels: [CGDirectDisplayID: Float] = [:]
                for d in displays {
                    var level: Float = 0
                    if get(d, &level) == 0 { levels[d] = level }
                }
                saved = levels
            }
            for d in displays { _ = set(d, night) }
            return "Night mode on: the built-in display's backlight off\(keyboard)."
        } else {
            guard let levels = saved else { return "Night mode off: nothing to put back\(keyboard)." }
            for (d, level) in levels { _ = set(d, level) }
            saved = nil
            return "Night mode off: the built-in display's brightness put back\(keyboard)."
        }
    }
}
