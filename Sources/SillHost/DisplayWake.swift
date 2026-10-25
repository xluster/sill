import Foundation
import CoreGraphics
import IOKit.pwr_mgt

/// The Mac's display, kept on for the devices. Display sleep stops a running ScreenCaptureKit
/// stream (SCStreamErrorDomain -3815, "no displays or windows to capture", measured 2026-10-25
/// with `pmset displaysleepnow`), and a stream started while the display sleeps delivers no frame
/// at all (0 fps for 9 s the same morning): a device saw black until someone at the Mac woke it.
/// So, as remote control apps do, the host turns the display on before it starts a capture
/// (`wake`, the call `caffeinate -u` makes) and holds idle display sleep off while a device is
/// connected (`hold`). Both are public IOKit power management calls; with no device connected
/// neither is held, and the display sleeps as the Mac's settings say.
@MainActor
final class DisplayWake {
    /// The PreventUserIdleDisplaySleep assertion while held, else 0.
    private var holdID: IOPMAssertionID = 0
    /// The user activity `wake` declared last, passed back on the next call as IOPMLib asks.
    private var activityID: IOPMAssertionID = 0

    /// The main display is asleep (display sleep, not the Mac's own sleep).
    static var isAsleep: Bool { CGDisplayIsAsleep(CGMainDisplayID()) != 0 }

    /// Idle display sleep held off while `on`. Calling it again with the same value does nothing.
    func hold(_ on: Bool) {
        if on, holdID == 0 {
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                     IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                     "Sill: a device is connected" as CFString, &id)
            if result == kIOReturnSuccess {
                holdID = id
                print("Display: kept on while a device is connected.")
            } else {
                print("Display: could not hold display sleep off (IOReturn \(result)).")
            }
        } else if !on, holdID != 0 {
            IOPMAssertionRelease(holdID)
            holdID = 0
            print("Display: may sleep again (no device connected).")
        }
    }

    /// Turns a sleeping display on and waits up to `timeout` for it to say so. True when it is on
    /// (at once when it was not asleep); false when it stayed asleep (a closed lid, a refusal),
    /// and the caller goes on as before this existed.
    func wake(timeout: TimeInterval = 3) async -> Bool {
        guard Self.isAsleep else { return true }
        let result = IOPMAssertionDeclareUserActivity("Sill: a device is watching" as CFString, kIOPMUserActiveLocal, &activityID)
        guard result == kIOReturnSuccess else {
            print("Display: could not wake it (IOReturn \(result)).")
            return false
        }
        let started = CFAbsoluteTimeGetCurrent()
        while Self.isAsleep {
            guard CFAbsoluteTimeGetCurrent() - started < timeout else {
                print("Display: still asleep \(Int(timeout)) s after the wake.")
                return false
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        print("Display: woken for a device in \(Int((CFAbsoluteTimeGetCurrent() - started) * 1000)) ms.")
        return true
    }
}
