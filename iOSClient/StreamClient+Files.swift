import Foundation
import UIKit
import UniformTypeIdentifiers
import StreamProtocol

/// A file going to the Mac, as the side keys show it.
struct FileSend: Equatable {
    enum State: Equatable { case sending, sent, failed(String) }
    var name: String
    var sent: Int64
    var size: Int64
    var state: State
    /// Files waiting behind this one.
    var waiting: Int
}

/// Files to the Mac (kind 35, FilePart.swift; Alexis, 2026-10-25): from Files or Photos through the
/// side keys, or a file copied on this device through Paste. One at a time, in parts of
/// `FilePart.partBytes`, at most four handed to the connection and not yet taken, then a ping whose
/// pong says the Mac has read the last part. The Mac keeps it in Downloads and puts it on its
/// clipboard.
extension StreamClient {
    private static let fileQueue = DispatchQueue(label: "sill.files.send", qos: .userInitiated)
    private static var waitingFiles = 0

    /// Sends the file at `url` after any already going. `scoped`: a URL from the document picker,
    /// opened for the read. `cleanup`: a copy of this app's own, removed once sent.
    func sendFile(at url: URL, name: String? = nil, scoped: Bool = false, cleanup: Bool = false) {
        guard connected, hostFiles else {
            #if DEBUG
            print("files: not sent (connected \(connected), the Mac takes files \(hostFiles))")
            #endif
            if UIDevice.current.userInterfaceIdiom == .phone { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
            if cleanup { try? FileManager.default.removeItem(at: url) }
            return
        }
        let name = FilePart.safeName(name ?? url.lastPathComponent)
        Self.waitingFiles += 1
        if var going = fileSend, going.state == .sending { going.waiting = Self.waitingFiles - 1; fileSend = going }
        Self.fileQueue.async { [weak self] in
            self?.transfer(url, name: name, scoped: scoped, cleanup: cleanup)
            DispatchQueue.main.async { Self.waitingFiles -= 1 }
        }
    }

    /// The pasteboard holds a file and neither text nor an image (a PDF copied in Files): sent as a
    /// file. False when it holds none, or the Mac takes no files.
    func pasteFileIfAny() -> Bool {
        let board = UIPasteboard.general
        guard hostFiles, !board.hasStrings, !board.hasImages, let provider = board.itemProviders.first,
              let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .data) == true })
        else { return false }
        let suggested = provider.suggestedName
        provider.loadFileRepresentation(forTypeIdentifier: type) { [weak self] url, _ in
            guard let url, let copy = Self.ownCopy(of: url) else {
                DispatchQueue.main.async { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
                return
            }
            var name = url.lastPathComponent
            if let suggested, !suggested.isEmpty {
                let ext = UTType(type)?.preferredFilenameExtension
                name = (suggested as NSString).pathExtension.isEmpty ? (ext.map { "\(suggested).\($0)" } ?? suggested) : suggested
            }
            DispatchQueue.main.async { self?.sendFile(at: copy, name: name, cleanup: true) }
        }
        return true
    }

    /// A copy of `url` in this app's temporary folder (a provider's file lasts only for its callback).
    static func ownCopy(of url: URL) -> URL? {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("sill-send", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let copy = folder.appendingPathComponent(url.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: copy)
            return copy
        } catch {
            return nil
        }
    }

    // MARK: The transfer, on `fileQueue`

    private func transfer(_ url: URL, name: String, scoped: Bool, cleanup: Bool) {
        let opened = scoped && url.startAccessingSecurityScopedResource()
        defer {
            if opened { url.stopAccessingSecurityScopedResource() }
            if cleanup { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        }
        let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else { return report(name, size: 0, .failed("\(name) is empty.")) }
        guard size <= FilePart.maxFileBytes else { return report(name, size: size, .failed("\(name) is over 2 GB.")) }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return report(name, size: size, .failed("\(name) couldn’t be read.")) }
        defer { try? handle.close() }

        let id = UUID().uuidString
        let window = DispatchSemaphore(value: 4)
        var offset: Int64 = 0
        var shownAt = Date.distantPast
        update(FileSend(name: name, sent: 0, size: size, state: .sending, waiting: 0))
        while offset < size {
            guard window.wait(timeout: .now() + 20) == .success,
                  let bytes = try? handle.read(upToCount: FilePart.partBytes), !bytes.isEmpty else {
                return report(name, size: size, .failed("\(name) didn’t reach the Mac."))
            }
            let payload = FilePart(id: id, name: name, size: size, offset: offset).payload(with: bytes)
            guard sendPaced(.file, payload: payload, done: { window.signal() }) else {
                return report(name, size: size, .failed("The connection to the Mac was lost."))
            }
            offset += Int64(bytes.count)
            if Date().timeIntervalSince(shownAt) > 0.1 || offset == size {
                shownAt = Date()
                update(FileSend(name: name, sent: offset, size: size, state: .sending, waiting: max(0, Self.waitingFiles - 1)))
            }
        }
        // The Mac has it once a ping sent after the last part comes back.
        let receipt = DispatchSemaphore(value: 0)
        let nonce = Data((0..<ClipboardPolicy.receiptLength).map { _ in UInt8.random(in: .min ... .max) })
        DispatchQueue.main.sync {
            fileNonce = nonce
            fileReceipt = receipt
            send(.ping, payload: nonce)
        }
        let came = receipt.wait(timeout: .now() + 60) == .success
        DispatchQueue.main.sync { fileReceipt = nil; if !came { fileNonce = nil } }
        report(name, size: size, came ? .sent : .failed("The Mac didn’t confirm \(name)."))
    }

    private func update(_ send: FileSend) {
        #if DEBUG
        print("files: \(send.name) \(send.sent) of \(send.size)")
        #endif
        DispatchQueue.main.async { self.fileSend = send }
    }

    /// The outcome, shown for a few seconds unless another file starts.
    private func report(_ name: String, size: Int64, _ state: FileSend.State) {
        let shown = FileSend(name: name, sent: size, size: size, state: state, waiting: 0)
        #if DEBUG
        print("files: \(name): \(state)")
        #endif
        DispatchQueue.main.async {
            self.fileSend = shown
            if UIDevice.current.userInterfaceIdiom == .phone {
                UINotificationFeedbackGenerator().notificationOccurred(state == .sent ? .success : .error)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + (state == .sent ? 3 : 5)) {
                if self.fileSend == shown { self.fileSend = nil }
            }
        }
    }
}
