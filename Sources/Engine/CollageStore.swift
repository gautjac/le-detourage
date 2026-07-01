import Foundation

/// Durable, always-on autosave for the *working* collage. The in-progress canvas
/// is written to a JSON file in Application Support (debounced by the caller) and
/// restored on launch, so closing the app never loses an arrangement — even one
/// the user never explicitly saved to the gallery.
///
/// Gallery collages are persisted separately via SwiftData (`SavedCollage`); this
/// store only owns the single working-draft file.
struct CollageStore {

    /// The working draft: the document plus the gallery row it is bound to (if
    /// any) so relaunching keeps "Save" updating the same page.
    struct Draft: Codable {
        var collageID: UUID?
        var title: String
        var document: CollageDocument
    }

    private let fileManager = FileManager.default

    private var directory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("LeDetourage", isDirectory: true)
    }

    private var workingURL: URL {
        directory.appendingPathComponent("working.collage.json")
    }

    /// Persist the working draft atomically. Safe to call off the main actor.
    func saveWorking(document: CollageDocument, collageID: UUID?, title: String) {
        let draft = Draft(collageID: collageID, title: title, document: document)
        guard let data = try? JSONEncoder().encode(draft) else { return }
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: workingURL, options: .atomic)
        } catch {
            // Autosave is best-effort; a failed write shouldn't disrupt editing.
        }
    }

    /// Load the working draft written by the last session, if any.
    func loadWorking() -> Draft? {
        guard let data = try? Data(contentsOf: workingURL) else { return nil }
        return try? JSONDecoder().decode(Draft.self, from: data)
    }

    /// Forget the working draft (e.g. after starting a brand-new collage).
    func clearWorking() {
        try? fileManager.removeItem(at: workingURL)
    }
}
