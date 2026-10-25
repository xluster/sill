import Foundation

/// Kind 33, host → device: whether the Mac's keyboard focus is in a place that takes text (a text
/// field, a text view, a terminal, a web page's field), so the device can bring its keyboard up by
/// itself and take it down again. Additive: older devices skip the kind.
public struct TextFocus: Codable, Equatable, Sendable {
    public var editable: Bool

    public init(editable: Bool) {
        self.editable = editable
    }
}
