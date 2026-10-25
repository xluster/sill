import Foundation
import Network
import StreamProtocol

/// Files from devices (kind 35, FilePart.swift; Alexis, 2026-10-25): each one's parts written in
/// order to a file of its own under the temporary folder, then moved into Downloads under a name not
/// taken there and put on the Mac's clipboard as a file (`onFile`). A part out of order, or a device
/// that leaves mid-file, drops that file. On a queue of its own: the disk never holds up the main
/// actor. One line per file, never its contents.
final class FileReceiver: @unchecked Sendable {   // state is confined to `queue`
    private let queue = DispatchQueue(label: "sill.files", qos: .userInitiated)
    private let folder: URL
    private let incoming: URL
    /// A file now in `folder`, on the queue; the coordinator hops to the main actor.
    var onFile: ((URL, String) -> Void)?

    private struct Transfer {
        let connection: ObjectIdentifier
        let name: String
        let size: Int64
        let url: URL
        let handle: FileHandle
        var received: Int64
    }
    private var transfers: [String: Transfer] = [:]

    /// `folder`: where finished files go (Downloads; a synthetic host's own with SILL_TEST_FILES_DIR).
    init(folder: URL) {
        self.folder = folder
        incoming = FileManager.default.temporaryDirectory.appendingPathComponent("sill-files", isDirectory: true)
    }

    func received(_ payload: Data, from connection: NWConnection, who: String) {
        let id = ObjectIdentifier(connection)
        queue.async { [self] in
            guard let (part, bytes) = FilePart.read(payload) else {
                print("File from \(who): a part that is not one; ignored.")
                return
            }
            var transfer: Transfer
            if let going = transfers[part.id] {
                guard going.connection == id, part.offset == going.received else {
                    drop(part.id, why: "a part out of order", who: who)
                    return
                }
                transfer = going
            } else {
                guard part.offset == 0 else { return }   // the rest of a file already dropped
                do {
                    try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
                    let url = incoming.appendingPathComponent(UUID().uuidString)
                    guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
                    transfer = Transfer(connection: id, name: FilePart.safeName(part.name), size: part.size, url: url,
                                        handle: try FileHandle(forWritingTo: url), received: 0)
                } catch {
                    print("File from \(who): could not be written (\(error.localizedDescription)).")
                    return
                }
            }
            do {
                try transfer.handle.write(contentsOf: bytes)
            } catch {
                transfers[part.id] = transfer
                drop(part.id, why: "could not be written (\(error.localizedDescription))", who: who)
                return
            }
            transfer.received += Int64(bytes.count)
            guard transfer.received >= transfer.size else {
                transfers[part.id] = transfer
                return
            }
            transfers[part.id] = nil
            try? transfer.handle.close()
            finish(transfer, who: who)
        }
    }

    /// A device left: its unfinished files are dropped, without a line.
    func clientLeft(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        queue.async { [self] in
            for (key, t) in transfers where t.connection == id {
                try? t.handle.close()
                try? FileManager.default.removeItem(at: t.url)
                transfers[key] = nil
            }
        }
    }

    private func finish(_ transfer: Transfer, who: String) {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = Self.free(transfer.name, in: folder)
            try FileManager.default.moveItem(at: transfer.url, to: destination)
            let size = ByteCountFormatter.string(fromByteCount: transfer.size, countStyle: .file)
            print("File from \(who): \(destination.lastPathComponent) (\(size)) in \(folder.lastPathComponent), on the clipboard.")
            onFile?(destination, who)
        } catch {
            try? FileManager.default.removeItem(at: transfer.url)
            print("File from \(who): could not be kept in \(folder.lastPathComponent) (\(error.localizedDescription)).")
        }
    }

    private func drop(_ key: String, why: String, who: String) {
        guard let t = transfers.removeValue(forKey: key) else { return }
        try? t.handle.close()
        try? FileManager.default.removeItem(at: t.url)
        print("File from \(who): \(t.name) dropped: \(why).")
    }

    /// `name` in `folder`, or "name 2.ext", "name 3.ext"… when it is taken, as the Finder does.
    static func free(_ name: String, in folder: URL) -> URL {
        let first = folder.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: first.path) else { return first }
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        for n in 2...9999 {
            let candidate = folder.appendingPathComponent(ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return folder.appendingPathComponent(UUID().uuidString + (ext.isEmpty ? "" : ".\(ext)"))
    }
}
