import AVFoundation
import Speech
import UIKit

/// Dictation without the software keyboard (Alexis, 2026-10-25): the side keys' microphone listens
/// and shows what it hears; nothing reaches the Mac until Send (`send`), and Discard drops it.
/// The microphone tapped again stops listening and keeps the words for Send; tapped once more it
/// goes on after them. Apple's speech recognition, on this device where it can be
/// (`requiresOnDeviceRecognition`), in the person's language (`recognizer`). Asks for the microphone
/// and speech recognition the first time.
@MainActor
final class Dictation: ObservableObject {
    @Published private(set) var listening = false
    /// The words waiting for Send: this time's, after any kept from before.
    @Published private(set) var heard = ""
    /// Why it could not listen, for a moment.
    @Published private(set) var problem: String?

    /// The words sent, to type on the Mac.
    var onText: (String) -> Void = { _ in }

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// Words kept: from an earlier listen this time, and this listen's utterances already over,
    /// which the next goes on after.
    private var kept = ""
    /// The utterance being heard now, as the recognizer last gave it.
    private var partial = ""
    /// The recognizer's whole text when the last utterance was kept: if it goes on giving the text
    /// from the start rather than starting afresh after a pause, that much is already kept.
    private var keptRaw = ""
    /// Send was tapped while listening: send once the recognizer settles.
    private var sendWhenSettled = false
    private var lastDelivery: Date?
    private var cap: DispatchWorkItem?

    /// One listen at most this long.
    private static let longest: TimeInterval = 55

    func toggle() { listening ? stop() : begin() }

    func begin() {
        guard !listening else { return }
        problem = nil
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard status == .authorized else {
                    self.fail("Allow Speech Recognition for Sill Alexis in Settings.")
                    return
                }
                AVAudioApplication.requestRecordPermission { granted in
                    Task { @MainActor in
                        guard granted else { self.fail("Allow the Microphone for Sill Alexis in Settings."); return }
                        self.start()
                    }
                }
            }
        }
    }

    /// Stops listening; the words wait for Send.
    func stop() {
        guard listening else { return }
        listening = false
        cap?.cancel()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Types the words on the Mac: at once, or, while listening, once the last of them is recognized.
    func send() {
        if listening {
            sendWhenSettled = true
            stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self, self.sendWhenSettled else { return }
                self.deliver()
            }
        } else {
            deliver()
        }
    }

    /// Drops the words, listening or not.
    func discard() {
        sendWhenSettled = false
        stop()
        release()
        kept = ""
        partial = ""
        keptRaw = ""
        heard = ""
    }

    private func start() {
        guard let recognizer = Self.recognizer(), recognizer.isAvailable else {
            fail("Dictation isn’t available right now.")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
            let input = engine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0), block: Self.feed(request))
            engine.prepare()
            try engine.start()
            self.request = request
            task = recognizer.recognitionTask(with: request, resultHandler: Self.results(self, request))
        } catch {
            fail("Dictation couldn’t start: \(error.localizedDescription)")
            return
        }
        kept = heard
        partial = ""
        keptRaw = ""
        sendWhenSettled = false
        listening = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let cap = DispatchWorkItem { [weak self] in self?.stop() }
        self.cap = cap
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.longest, execute: cap)
    }

    /// The person's own language: the first of their preferred languages that speech recognition
    /// knows (French before English for a French iPhone). `Locale.current` would not do: an app
    /// localized only in English gets an English locale whatever the iPhone speaks.
    private static func recognizer() -> SFSpeechRecognizer? {
        for id in Locale.preferredLanguages {
            if let r = SFSpeechRecognizer(locale: Locale(identifier: id)), r.isAvailable { return r }
        }
        return SFSpeechRecognizer()
    }

    /// The tap runs on the audio thread: built outside the main actor.
    private nonisolated static func feed(_ request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        { buffer, _ in request.append(buffer) }
    }

    private nonisolated static func results(_ owner: Dictation, _ request: SFSpeechAudioBufferRecognitionRequest)
        -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { [weak owner] result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            // Set on the result that ends an utterance, at a pause.
            let ended = result?.speechRecognitionMetadata != nil
            let failed = error != nil
            Task { @MainActor in owner?.received(text, final: final, ended: ended, failed: failed, from: request) }
        }
    }

    /// A result of `from`'s listen; one from a listen already let go (its cancel's error) is ignored.
    ///
    /// After a long enough pause the recognizer starts its text afresh, and before this the words
    /// before the pause were lost from `heard` (Alexis, 2026-10-25). Each utterance is kept when it
    /// ends (`ended`, the result that carries its metadata), or when the text plainly starts over.
    private func received(_ text: String?, final: Bool, ended: Bool, failed: Bool,
                          from: SFSpeechAudioBufferRecognitionRequest) {
        guard from === request else { return }
        if let raw = text {
            var now = raw
            if !keptRaw.isEmpty, raw.hasPrefix(keptRaw) {
                // The recognizer did not start afresh: what it already said is kept.
                now = String(raw.dropFirst(keptRaw.count)).trimmingCharacters(in: .whitespaces)
            } else if Self.startsOver(from: partial, to: now) {
                keep(partial, raw: "")
            }
            partial = now
            heard = Self.join(kept, partial)
            if ended, !partial.isEmpty { keep(partial, raw: raw) }
        }
        guard final || failed else { return }
        if listening { stop() }
        release()
        if sendWhenSettled { deliver() }
    }

    /// The utterance heard so far goes into `kept`.
    private func keep(_ utterance: String, raw: String) {
        guard !utterance.isEmpty else { return }
        kept = Self.join(kept, utterance)
        partial = ""
        keptRaw = raw
    }

    /// Whether the recognizer's text started over rather than grew: shorter by more than a word's
    /// worth, and beginning with another word.
    private static func startsOver(from old: String, to new: String) -> Bool {
        guard !old.isEmpty, new.count + 4 < old.count else { return false }
        let first = { (s: String) in s.split(separator: " ").first.map { $0.lowercased() } ?? "" }
        return first(old) != first(new)
    }

    private static func join(_ a: String, _ b: String) -> String {
        a.isEmpty ? b : (b.isEmpty ? a : a + " " + b)
    }

    /// Lets the recognizer and the microphone go.
    private func release() {
        task?.cancel(); task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Types the words on the Mac, and clears them.
    private func deliver() {
        sendWhenSettled = false
        release()
        let text = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        kept = ""
        partial = ""
        keptRaw = ""
        heard = ""
        guard !text.isEmpty else { return }
        // A second dictation soon after the first goes on after it, not glued to its full stop.
        let joined = (lastDelivery.map { Date().timeIntervalSince($0) < 120 } ?? false) ? " " + text : text
        onText(joined)
        lastDelivery = Date()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func fail(_ why: String) {
        listening = false
        problem = why
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            if self?.problem == why { self?.problem = nil }
        }
    }
}
