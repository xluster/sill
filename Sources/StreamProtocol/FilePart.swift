import Foundation

/// Device → host (kind 35): a file sent from the device, in parts of at most `partBytes`, in order
/// (Alexis, 2026-10-25). The host keeps it in Downloads and puts it on the Mac's clipboard as a
/// file. Sent only to a host whose window list says `files` 1.
///
/// The payload: the length of the JSON below (4 bytes, big-endian), that JSON, then the part's bytes.
public struct FilePart: Codable, Equatable, Sendable {
    /// One file's parts share it (a UUID string).
    public var id: String
    /// The file's name, on every part (the host takes the first part's).
    public var name: String
    /// The whole file's size in bytes.
    public var size: Int64
    /// Where this part's bytes begin in the file.
    public var offset: Int64

    public init(id: String, name: String, size: Int64, offset: Int64) {
        self.id = id; self.name = name; self.size = size; self.offset = offset
    }

    /// The bytes in one part: with its header it stays under the host's cap on a device's message
    /// (`StreamMessage.maxClientPayload`, 1 MiB).
    public static let partBytes = 512 * 1024
    /// The largest file a device sends.
    public static let maxFileBytes: Int64 = 2 * 1024 * 1024 * 1024
    /// What `WindowList.files` says for this generation.
    public static let generation = 1

    /// The message's payload for this part and its bytes.
    public func payload(with bytes: Data) -> Data {
        let json = (try? JSONEncoder().encode(self)) ?? Data()
        var data = Data(capacity: 4 + json.count + bytes.count)
        withUnsafeBytes(of: UInt32(json.count).bigEndian) { data.append(contentsOf: $0) }
        data.append(json)
        data.append(bytes)
        return data
    }

    /// The part and its bytes, or nil for a payload that is not one (a header that does not fit or
    /// decode, a size out of bounds, bytes past the file's end).
    public static func read(_ payload: Data) -> (part: FilePart, bytes: Data)? {
        guard payload.count >= 4 else { return nil }
        let start = payload.startIndex
        let length = payload[start..<start + 4].reduce(0) { $0 << 8 | Int($1) }
        guard length > 0, 4 + length <= payload.count,
              let part = try? JSONDecoder().decode(FilePart.self, from: payload[start + 4..<start + 4 + length]) else { return nil }
        let bytes = Data(payload[(start + 4 + length)...])
        guard part.size > 0, part.size <= maxFileBytes, part.offset >= 0,
              part.offset + Int64(bytes.count) <= part.size, !part.id.isEmpty, part.id.count <= 64 else { return nil }
        return (part, bytes)
    }

    /// A name safe to give a file in Downloads: its last path component, no leading dots, no
    /// separators or control characters, at most 200 characters; "File" when nothing is left.
    public static func safeName(_ name: String) -> String {
        let last = name.split(separator: "/").last.map(String.init) ?? name
        var cleaned = String(last.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && $0 != ":" })
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        if cleaned.count > 200 { cleaned = String(cleaned.suffix(200)) }
        return cleaned.isEmpty ? "File" : cleaned
    }
}
