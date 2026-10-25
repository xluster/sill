import Foundation

/// Device → host (kind 36): night mode (Alexis, 2026-10-25). On, the host takes the Mac's built-in
/// display to its lowest brightness, keeping what it was; off, it puts that back. The picture keeps
/// streaming (the display stays awake). Sent only to a host whose window list says `night` 1.
public struct Night: Codable, Equatable, Sendable {
    public var on: Bool
    public init(on: Bool) { self.on = on }
}
