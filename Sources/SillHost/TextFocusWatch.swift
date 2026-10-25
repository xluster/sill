import ApplicationServices
import Foundation

/// Whether the Mac's keyboard focus is in a place that takes text, looked at four times a second
/// while a device is connected, so the device can bring its keyboard up by itself (kind 33, Alexis
/// 2026-10-25). Accessibility, read-only; without the permission it never sees a text field. On a
/// queue of its own, so an app slow to answer never holds the main actor.
final class TextFocusWatch: @unchecked Sendable {   // state is confined to `queue`
    private let queue = DispatchQueue(label: "sill.textfocus", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var last: Bool?
    /// Each change, on `queue`; the coordinator hops to the main actor.
    var onChange: ((Bool) -> Void)?

    /// Looks from now on; already looking, the next look reports whatever it finds (a device that
    /// just connected hears the focus as it is).
    func start() {
        queue.async { [self] in
            last = nil
            guard timer == nil else { return }
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now(), repeating: .milliseconds(250), leeway: .milliseconds(50))
            t.setEventHandler { [weak self] in self?.look() }
            timer = t
            t.resume()
        }
    }

    func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            last = nil
        }
    }

    private func look() {
        let now = Self.focusTakesText()
        guard now != last else { return }
        last = now
        onChange?(now)
    }

    /// The focused element of the app in front: a text field, text area, combo or search field, or
    /// anything whose value can be set and that has a selected text range (a web page's field, a
    /// code editor).
    static func focusTakesText() -> Bool {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.2)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return false }
        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.2)
        var role: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        if let role = role as? String,
           [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField"].contains(role) {
            return true
        }
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success,
              settable.boolValue else { return false }
        var range: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success
    }
}
