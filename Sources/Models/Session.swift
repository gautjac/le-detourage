import SwiftUI
import SwiftData
import Observation

/// App-wide, non-persisted session state: the working collage, the photo
/// currently loaded into the cutout stage, transient busy/toast flags, the
/// selected element, plus the undo history and the autosave/gallery plumbing.
@Observable
@MainActor
final class Session {
    /// The live collage document.
    let collage = Collage()

    /// The photo loaded into the cutout stage (nil until one is imported).
    var stageImage: PlatformImage?

    /// The currently selected placed element on the canvas (for the inspector).
    var selection: PlacedSticker?

    /// A cut-out currently in flight (drives spinners / disables controls).
    var isLifting = false

    /// A short-lived toast message shown after actions.
    var toast: String?
    private var toastTask: Task<Void, Never>?

    /// Which top-level tab is showing.
    var tab: Tab = .atelier
    enum Tab: Hashable { case atelier, tiroir }

    // MARK: History + persistence

    let history = CollageHistory()
    private let store = CollageStore()
    private var autosaveTask: Task<Void, Never>?

    /// The gallery page this working collage is bound to (nil = an unsaved draft).
    var currentCollageID: UUID?
    /// The working title (shown in the canvas header; editable via Save/Gallery).
    var currentTitle: String = ""

    /// The text element currently being composed/edited (drives the editor sheet).
    var editingText: PlacedSticker?
    /// True while `editingText` is a freshly-added, not-yet-committed label, so a
    /// cancel can clean it up.
    var editingTextIsNew = false

    init() {
        restore()
    }

    // MARK: Stage

    /// Load a photo into the cutout stage.
    func loadStage(_ image: PlatformImage) {
        stageImage = image
    }

    /// Load the bundled sample photo.
    func loadSample() {
        if let s = SampleImage.make() { stageImage = s }
    }

    // MARK: Toast

    /// Show a toast for ~2 seconds.
    func flash(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if !Task.isCancelled { self?.toast = nil }
        }
    }

    // MARK: Editing checkpoints

    /// Record an undoable checkpoint of the current state and arm an autosave.
    /// Call this immediately *before* any committed mutation to the collage.
    func checkpoint() {
        history.record(collage.snapshot())
        scheduleAutosave()
    }

    /// Undo the last committed edit.
    func undo() {
        guard let snapshot = history.undo(current: collage.snapshot()) else { return }
        apply(snapshot)
    }

    /// Redo the last undone edit.
    func redo() {
        guard let snapshot = history.redo(current: collage.snapshot()) else { return }
        apply(snapshot)
    }

    private func apply(_ snapshot: CollageSnapshot) {
        let selectedID = selection?.id
        collage.restore(snapshot)
        // Re-map the selection onto the freshly-rebuilt element instances.
        selection = selectedID.flatMap { id in collage.stickers.first { $0.id == id } }
        editingText = nil
        scheduleAutosave()
        Haptics.tap()
    }

    // MARK: Placing

    /// Add a lifted cutout to the collage, select it, and switch to the studio.
    @discardableResult
    func placeOnCanvas(_ image: PlatformImage, sourceID: UUID? = nil) -> PlacedSticker {
        checkpoint()
        let placed = collage.add(image: image, sourceID: sourceID)
        selection = placed
        Haptics.success()
        return placed
    }

    // MARK: Text

    /// Add a blank text label at the center and open the editor for it.
    func addText() {
        checkpoint()
        let placed = collage.addText(TextContent())
        selection = placed
        editingText = placed
        editingTextIsNew = true
        Haptics.success()
    }

    /// Open the editor for an existing text element.
    func editText(_ sticker: PlacedSticker) {
        guard sticker.isText else { return }
        checkpoint()
        selection = sticker
        editingText = sticker
        editingTextIsNew = false
    }

    /// Finish editing text. If a brand-new label was left empty, remove it and
    /// undo the checkpoint so it leaves no trace.
    func finishEditingText(cancelled: Bool) {
        defer { editingText = nil; editingTextIsNew = false }
        guard let sticker = editingText else { return }
        let empty = sticker.text?.isEffectivelyEmpty ?? true
        if editingTextIsNew && (cancelled || empty) {
            collage.remove(sticker)
            if selection?.id == sticker.id { selection = nil }
            history.discardLast()
        }
        scheduleAutosave()
    }

    // MARK: Autosave / restore

    /// Debounced write of the working collage to the durable draft file.
    func scheduleAutosave() {
        autosaveTask?.cancel()
        let document = collage.document
        let id = currentCollageID
        let title = currentTitle
        let store = self.store
        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
            store.saveWorking(document: document, collageID: id, title: title)
        }
    }

    /// Write the working collage immediately (on background/terminate).
    func flushAutosave() {
        autosaveTask?.cancel()
        store.saveWorking(document: collage.document, collageID: currentCollageID, title: currentTitle)
    }

    /// Restore the working draft written by the previous session.
    private func restore() {
        guard let draft = store.loadWorking() else { return }
        collage.load(document: draft.document)
        currentCollageID = draft.collageID
        currentTitle = draft.title
        history.reset()
    }

    // MARK: Gallery

    /// Save (or update) the current collage as a gallery page.
    @discardableResult
    func saveToGallery(context: ModelContext) -> Bool {
        guard !collage.isEmpty else { return false }
        let thumb = CollageRenderer.render(collage, transparentBackground: false, longEdge: 512)
        guard let thumbData = thumb?.pngData,
              let docData = try? JSONEncoder().encode(collage.document) else { return false }

        if let id = currentCollageID,
           let existing = try? context.fetch(
               FetchDescriptor<SavedCollage>(predicate: #Predicate { $0.id == id })).first {
            existing.thumbnailData = thumbData
            existing.documentData = docData
            existing.updatedAt = Date()
            if !currentTitle.isEmpty { existing.title = currentTitle }
        } else {
            let title = currentTitle.isEmpty ? defaultTitle(in: context) : currentTitle
            let page = SavedCollage(title: title, thumbnailData: thumbData, documentData: docData)
            context.insert(page)
            currentCollageID = page.id
            currentTitle = title
        }
        try? context.save()
        scheduleAutosave()
        Haptics.success()
        flash(L.t("gallery.saved"))
        return true
    }

    /// Open a saved gallery page into the working canvas.
    func open(_ page: SavedCollage) {
        collage.load(document: page.document)
        currentCollageID = page.id
        currentTitle = page.title
        selection = nil
        editingText = nil
        history.reset()
        tab = .atelier
        scheduleAutosave()
        Haptics.success()
    }

    /// Start a fresh, empty collage (the current one should already be saved or
    /// autosaved).
    func newCollage() {
        checkpoint()
        collage.clear()
        collage.background = .color(Theme.page)
        collage.backgroundImage = nil
        selection = nil
        editingText = nil
        currentCollageID = nil
        currentTitle = ""
        history.reset()
        scheduleAutosave()
    }

    /// A sensible default name for a newly-saved page: "Collage N".
    private func defaultTitle(in context: ModelContext) -> String {
        let count = (try? context.fetchCount(FetchDescriptor<SavedCollage>())) ?? 0
        return "\(L.t("gallery.untitled")) \(count + 1)"
    }
}
