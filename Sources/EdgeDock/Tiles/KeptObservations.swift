import Foundation

/// KVO observations kept together with the objects they observe. Each object is held strongly
/// for as long as its observation lives: an object deallocated while still observed logs
/// "deallocated while key value observers were still registered" and risks a crash (REG-021).
@MainActor final class KeptObservations<Key: Hashable, Subject: NSObject> {
    private var entries: [Key: (subject: Subject, observation: NSKeyValueObservation)] = [:]

    func contains(_ key: Key) -> Bool { entries[key] != nil }

    func insert(_ subject: Subject, for key: Key, observation: NSKeyValueObservation) {
        entries[key]?.observation.invalidate()
        entries[key] = (subject, observation)
    }

    /// Invalidates the matching observations, then releases their objects.
    func removeAll(where drop: (Subject) -> Bool) {
        for (key, entry) in entries where drop(entry.subject) {
            entry.observation.invalidate()
            entries[key] = nil
        }
    }
}
