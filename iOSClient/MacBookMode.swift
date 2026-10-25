import SwiftUI
import StreamProtocol

/// MacBook mode (Alexis, 2026-10-25): in the laptop pose the lower half becomes a MacBook's deck,
/// an aluminium top case with a French (AZERTY) keyboard and a trackpad, and the upper half its
/// screen in a black bezel with an aluminium edge; folded shut, the cover shows the closed lid with
/// the Apple logo. Kept across launches (`Sill.macBookMode`); the Touch ID key leaves it.
///
/// The keys send the physical key each one is on a French Mac keyboard (its HID usage), so the
/// Mac's own French layout makes the character the cap shows: A is sent as the US layout's Q key,
/// "@ #" as the ISO key left of 1. Modifiers latch for the next key, as the key row's do.
enum MacBookMode {
    static let key = "Sill.macBookMode"
}

// MARK: - The colours

enum Aluminium {
    static let light = Color(hex: 0xE3E4E6)
    static let mid = Color(hex: 0xCDCFD2)
    static let dark = Color(hex: 0xA9ACB1)
    static let edge = Color(hex: 0x8E9196)
    static let keyTop = Color(hex: 0x1C1C1E)
    static let keyPressed = Color(hex: 0x3A3A3C)
    static let well = Color(hex: 0xB8BBBF)

    static var deck: LinearGradient {
        LinearGradient(colors: [light, mid], startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - The screen

/// The picture as a MacBook's screen: a black bezel, rounder at the top, a thin aluminium edge
/// around it and the camera's notch at the top centre.
struct MacBookScreen<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        let lid = UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 6,
                                         bottomTrailingRadius: 6, topTrailingRadius: 22, style: .continuous)
        content()
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .padding(.horizontal, 10)
            .padding(.top, 16)
            .padding(.bottom, 10)
            .background(lid.fill(Color(hex: 0x0B0B0C)))
            .overlay(alignment: .top) {
                // The notch, with the camera's lens.
                UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6, style: .continuous)
                    .fill(Color(hex: 0x0B0B0C))
                    .frame(width: 92, height: 18)
                    .overlay(Circle().fill(Color(hex: 0x1E2A35)).frame(width: 5, height: 5).offset(y: -1))
                    .padding(.top, 2)
                    .allowsHitTesting(false)
            }
            .overlay(lid.strokeBorder(LinearGradient(colors: [Aluminium.light, Aluminium.edge],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 2.5))
    }
}

// MARK: - The closed lid

/// The cover while MacBook mode is on and the Duo is shut: the lid of a closed MacBook, aluminium
/// with the Apple logo in its middle.
struct MacBookLid: View {
    var body: some View {
        ZStack {
            Color.black
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xD9DBDE), Color(hex: 0xBFC2C6), Color(hex: 0xD2D4D7)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.7), Aluminium.edge],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 2)
                )
                .overlay(
                    Image(systemName: "apple.logo")
                        .font(.system(size: 88, weight: .regular))
                        .foregroundStyle(LinearGradient(colors: [Color(hex: 0xF4F5F6), Color(hex: 0xA7AAAF)],
                                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: .white.opacity(0.6), radius: 0.5, x: -0.5, y: -0.5)
                        .shadow(color: .black.opacity(0.18), radius: 1, x: 0.5, y: 0.8)
                )
                .padding(10)
        }
        .ignoresSafeArea()
        .accessibilityElement()
        .accessibilityLabel("MacBook closed. Open the iPhone to use the Mac.")
    }
}

// MARK: - The deck

/// The lower half: the keyboard and, under it, the trackpad, on the aluminium top case.
struct MacBookDeck<Pad: View>: View {
    @Binding var latched: KeyModifiers
    let send: (InputEvent) -> Void
    let leave: () -> Void
    /// F6, the moon on a real MacBook: night mode (NightMode).
    var nightOn = false
    var night: () -> Void = {}
    @ViewBuilder let trackpad: () -> Pad

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            VStack(spacing: 14) {
                MacBookKeyboard(latched: $latched, send: send, leave: leave, nightOn: nightOn, night: night, width: width - 24)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Aluminium.well))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.12), lineWidth: 1))
                trackpad()
                    .frame(width: min(width * 0.62, 420))
                    .frame(maxHeight: .infinity)
                    .padding(.bottom, 14)
            }
            .padding(.top, 12)
            .padding(.horizontal, 6)
            .frame(width: width, height: geo.size.height)
            // Back to the usual arrangement, beside the trackpad (the Touch ID key does it too).
            .overlay(alignment: .bottomLeading) {
                Button(action: leave) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 11, weight: .bold))
                        Text("Normal")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Color(hex: 0x3A3B3E))
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Capsule().fill(Color.white.opacity(0.55)))
                    .overlay(Capsule().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
                    .contentShape(Capsule())
                }
                .buttonStyle(MacKeyPress())
                .accessibilityLabel("Leave MacBook mode")
                .padding(.leading, 18)
                .padding(.bottom, 22)
            }
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 26,
                                       bottomTrailingRadius: 26, topTrailingRadius: 8, style: .continuous)
                    .fill(Aluminium.deck)
                    .overlay(
                        UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 26,
                                               bottomTrailingRadius: 26, topTrailingRadius: 8, style: .continuous)
                            .strokeBorder(Aluminium.edge.opacity(0.6), lineWidth: 1)
                    )
            )
        }
    }
}

/// The trackpad's glass on the aluminium: a slightly darker panel, no texture, no words.
struct MacBookTrackpadSurface: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        content
            .background(shape.fill(LinearGradient(colors: [Color(hex: 0xD4D6D9), Color(hex: 0xC4C7CB)],
                                                   startPoint: .top, endPoint: .bottom)))
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.black.opacity(0.14), lineWidth: 1))
    }
}

// MARK: - The keyboard

/// A French MacBook keyboard: the function row, then five rows, 14.5 key widths across.
struct MacBookKeyboard: View {
    @Binding var latched: KeyModifiers
    let send: (InputEvent) -> Void
    let leave: () -> Void
    var nightOn = false
    var night: () -> Void = {}
    let width: CGFloat

    @State private var capsOn = false
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    private static let gap: CGFloat = 4
    private static let units: CGFloat = 14.5
    /// A row is 14.5 key widths and, with the wider keys' own, 13.5 gaps.
    private var unit: CGFloat { (width - 13.5 * Self.gap) / Self.units }
    private var rowHeight: CGFloat { min(40, unit * 0.92) }

    /// One key: what it shows, how wide it is, what it does.
    private struct Key {
        enum Action { case usage(UInt16), modifier(KeyModifiers), caps, leave, night }
        var main: String
        var shifted: String? = nil
        var symbol: String? = nil
        var width: CGFloat = 1
        var action: Action
        var small = false
        /// Where its label sits: centred (letters), or at a corner (the wide keys, as on a Mac).
        var corner: Alignment = .center
    }

    private static func letter(_ c: String, _ usage: UInt16) -> Key { Key(main: c, action: .usage(usage)) }
    private static func pair(_ shifted: String, _ main: String, _ usage: UInt16) -> Key {
        Key(main: main, shifted: shifted, action: .usage(usage))
    }

    private static let function: [Key] = {
        var row = [Key(main: "esc", width: 1.5, action: .usage(0x29), small: true, corner: .bottomLeading)]
        for n in 1...12 {
            // F6 is the moon on a MacBook: here, night mode.
            row.append(n == 6 ? Key(main: "F6", symbol: "moon.fill", action: .night, small: true)
                              : Key(main: "F\(n)", action: .usage(UInt16(0x39 + n)), small: true))
        }
        row.append(Key(main: "", symbol: "touchid", action: .leave))
        return row
    }()

    private static let numbers: [Key] = [
        pair("#", "@", 0x64), pair("1", "&", 0x1E), pair("2", "é", 0x1F), pair("3", "\"", 0x20),
        pair("4", "'", 0x21), pair("5", "(", 0x22), pair("6", "§", 0x23), pair("7", "è", 0x24),
        pair("8", "!", 0x25), pair("9", "ç", 0x26), pair("0", "à", 0x27), pair("°", ")", 0x2D),
        pair("_", "-", 0x2E),
        Key(main: "delete", symbol: "delete.left", width: 1.5, action: .usage(0x2A), small: true, corner: .bottomTrailing),
    ]

    private static let top: [Key] = [
        Key(main: "tab", symbol: "arrow.right.to.line", width: 1.5, action: .usage(0x2B), small: true, corner: .bottomLeading),
        letter("A", 0x14), letter("Z", 0x1A), letter("E", 0x08), letter("R", 0x15), letter("T", 0x17),
        letter("Y", 0x1C), letter("U", 0x18), letter("I", 0x0C), letter("O", 0x12), letter("P", 0x13),
        pair("¨", "^", 0x2F), pair("*", "$", 0x30), pair("£", "`", 0x31),
    ]

    private static let home: [Key] = [
        Key(main: "caps lock", width: 1.75, action: .caps, small: true, corner: .bottomLeading),
        letter("Q", 0x04), letter("S", 0x16), letter("D", 0x07), letter("F", 0x09), letter("G", 0x0A),
        letter("H", 0x0B), letter("J", 0x0D), letter("K", 0x0E), letter("L", 0x0F), letter("M", 0x33),
        pair("%", "ù", 0x34),
        Key(main: "return", symbol: "return", width: 1.75, action: .usage(0x28), small: true, corner: .bottomTrailing),
    ]

    private static let bottom: [Key] = [
        Key(main: "shift", symbol: "shift", width: 1.25, action: .modifier(.shift), small: true, corner: .bottomLeading),
        pair(">", "<", 0x35),
        letter("W", 0x1D), letter("X", 0x1B), letter("C", 0x06), letter("V", 0x19), letter("B", 0x05),
        letter("N", 0x11), pair("?", ",", 0x10), pair(".", ";", 0x36), pair("/", ":", 0x37), pair("+", "=", 0x38),
        Key(main: "shift", symbol: "shift", width: 2.25, action: .modifier(.shift), small: true, corner: .bottomTrailing),
    ]

    private static let space: [Key] = [
        Key(main: "control", symbol: "control", width: 1.25, action: .modifier(.control), small: true, corner: .bottomLeading),
        Key(main: "option", symbol: "option", width: 1.25, action: .modifier(.option), small: true, corner: .bottomLeading),
        Key(main: "command", symbol: "command", width: 1.5, action: .modifier(.command), small: true, corner: .bottomLeading),
        Key(main: "", width: 4.75, action: .usage(0x2C)),
        Key(main: "command", symbol: "command", width: 1.5, action: .modifier(.command), small: true, corner: .bottomTrailing),
        Key(main: "option", symbol: "option", width: 1.25, action: .modifier(.option), small: true, corner: .bottomTrailing),
    ]

    var body: some View {
        VStack(spacing: Self.gap) {
            row(Self.function, height: rowHeight * 0.62)
            row(Self.numbers)
            row(Self.top)
            row(Self.home)
            row(Self.bottom)
            HStack(spacing: Self.gap) {
                row(Self.space)
                arrows
            }
        }
        .frame(width: width)
    }

    private func row(_ keys: [Key], height: CGFloat? = nil) -> some View {
        HStack(spacing: Self.gap) {
            ForEach(keys.indices, id: \.self) { i in
                cap(keys[i], height: height ?? rowHeight)
            }
        }
    }

    /// ← and →, full height, with ↑ over ↓ at half height between them, as on a MacBook.
    private var arrows: some View {
        HStack(alignment: .bottom, spacing: Self.gap) {
            arrow("arrowtriangle.left.fill", 0x50, height: rowHeight / 2 - 1)
            VStack(spacing: 2) {
                arrow("arrowtriangle.up.fill", 0x52, height: rowHeight / 2 - 1)
                arrow("arrowtriangle.down.fill", 0x51, height: rowHeight / 2 - 1)
            }
            arrow("arrowtriangle.right.fill", 0x4F, height: rowHeight / 2 - 1)
        }
        .frame(height: rowHeight, alignment: .bottom)
    }

    private func arrow(_ symbol: String, _ usage: UInt16, height: CGFloat) -> some View {
        cap(Key(main: "", symbol: symbol, action: .usage(usage)), height: height)
    }

    private func cap(_ key: Key, height: CGFloat) -> some View {
        let w = key.width * unit + (key.width - 1) * Self.gap
        let on: Bool = {
            switch key.action {
            case .modifier(let flag): return latched.contains(flag)
            case .caps: return capsOn
            case .night: return nightOn
            default: return false
            }
        }()
        return Button { press(key) } label: {
            label(key, on: on, height: height)
                .frame(width: max(w, 1), height: height)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Aluminium.keyTop))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(on ? Color.white.opacity(0.75) : Color.white.opacity(0.06), lineWidth: on ? 1.5 : 0.5))
                .shadow(color: .black.opacity(0.25), radius: 0.5, y: 0.8)
                .contentShape(Rectangle())
        }
        .buttonStyle(MacKeyPress())
        .accessibilityLabel(accessibilityName(key))
    }

    @ViewBuilder
    private func label(_ key: Key, on: Bool, height: CGFloat) -> some View {
        let ink = Color.white.opacity(0.92)
        if case .leave = key.action {
            // Touch ID's ring; here it leaves MacBook mode.
            Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                .frame(width: height * 0.7, height: height * 0.7)
                .overlay(Image(systemName: "power").font(.system(size: height * 0.32, weight: .medium)).foregroundStyle(ink))
        } else if key.small {
            ZStack(alignment: key.corner) {
                Color.clear
                VStack(alignment: key.corner == .bottomTrailing ? .trailing : .leading, spacing: 1) {
                    if let symbol = key.symbol {
                        // On the function row (short keys) the symbol alone, as F6's moon.
                        Image(systemName: symbol).font(.system(size: height > 28 ? 10 : 9, weight: .medium))
                    }
                    if key.symbol == nil || height > 28 {
                        Text(key.main).font(.system(size: height > 28 ? 8.5 : 9, weight: .medium)).lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                .foregroundStyle(ink)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                if case .caps = key.action {
                    Circle().fill(capsOn ? Color(hex: 0x30D158) : Color.white.opacity(0.18))
                        .frame(width: 4, height: 4)
                        .padding(5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        } else if let shifted = key.shifted {
            VStack(spacing: 0) {
                Text(shifted).font(.system(size: 10.5, weight: .regular))
                Text(key.main).font(.system(size: 13, weight: .regular))
            }
            .foregroundStyle(ink)
        } else if let symbol = key.symbol {
            Image(systemName: symbol).font(.system(size: 8, weight: .semibold)).foregroundStyle(ink)
        } else {
            Text(key.main).font(.system(size: 15, weight: .regular)).foregroundStyle(ink)
        }
    }

    private func press(_ key: Key) {
        haptic.impactOccurred(intensity: 0.5)
        switch key.action {
        case .usage(let usage):
            KeyChord.press(usage, with: latched).forEach(send)
            latched = []
        case .modifier(let flag):
            latched.formSymmetricDifference(flag)
        case .caps:
            capsOn.toggle()
            KeyChord.press(0x39, with: []).forEach(send)
        case .leave:
            leave()
        case .night:
            night()
        }
    }

    private func accessibilityName(_ key: Key) -> String {
        switch key.action {
        case .leave: return "Leave MacBook mode"
        case .night: return nightOn ? "Night mode, on" : "Night mode"
        case .usage(0x2C): return "Space"
        default:
            if let shifted = key.shifted { return "\(key.main), \(shifted)" }
            return key.main.isEmpty ? (key.symbol ?? "Key") : key.main
        }
    }
}

/// A key going down: a touch darker and smaller.
private struct MacKeyPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .brightness(configuration.isPressed ? 0.08 : 0)
            .animation(.easeOut(duration: 0.06), value: configuration.isPressed)
    }
}

// MARK: - Night mode

/// Night mode (Alexis, 2026-10-25): the Mac's built-in display at its lowest brightness (kind 36,
/// where the Mac takes it) and this device's screen at its lowest too, each put back as it was when
/// it goes off. Kept across launches (`Sill.night`), with this screen's brightness from before.
enum NightMode {
    static let key = "Sill.night"
    private static let brightnessKey = "Sill.nightBrightness"

    static func apply(_ on: Bool, client: StreamClient) {
        let defaults = UserDefaults.standard
        defaults.set(on, forKey: key)
        if on {
            if defaults.object(forKey: brightnessKey) == nil {
                defaults.set(Double(UIScreen.main.brightness), forKey: brightnessKey)
            }
            UIScreen.main.brightness = 0
        } else if let before = defaults.object(forKey: brightnessKey) as? Double {
            UIScreen.main.brightness = CGFloat(before)
            defaults.removeObject(forKey: brightnessKey)
        }
        if client.hostNight { client.send(.night, payload: Wire.encode(Night(on: on))) }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
}
