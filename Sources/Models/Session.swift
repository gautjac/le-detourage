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

    /// The set of selected elements' ids (the source of truth for selection).
    var selectedIDs: Set<UUID> = []

    /// The single selected element (for the per-element inspector), or nil when
    /// nothing or multiple things are selected. Setting it replaces the whole
    /// selection — so existing single-select call sites keep working.
    var selection: PlacedSticker? {
        get {
            guard selectedIDs.count == 1, let id = selectedIDs.first else { return nil }
            return collage.stickers.first { $0.id == id }
        }
        set { selectedIDs = newValue.map { [$0.id] } ?? [] }
    }

    /// The selected elements, back-to-front.
    var selectedStickers: [PlacedSticker] { collage.selected(selectedIDs) }
    var isMultiSelect: Bool { selectedIDs.count > 1 }

    /// Live group-drag translation (page points) while multiple elements move
    /// together, and whether such a drag is active.
    var groupDrag: CGSize = .zero
    var groupDragging = false

    /// Copied elements' documents, for macOS copy/paste.
    var clipboard: [ElementDTO] = []

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

    /// The cutout currently being styled (drives the filter/outline sheet).
    var editingStyle: PlacedSticker?

    /// The cutout currently being cleaned up (drives the erase/feather sheet).
    var cleaningCutout: PlacedSticker?

    /// Whether the freehand doodle editor is active.
    var isDrawing = false

    /// Alignment guide lines to draw while an element is being dragged.
    var activeGuides: [AlignmentGuide] = []

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
        let ids = selectedIDs
        collage.restore(snapshot)
        // Keep whichever selected ids still exist after the restore.
        selectedIDs = ids.intersection(Set(collage.stickers.map(\.id)))
        editingText = nil
        scheduleAutosave()
        Haptics.tap()
    }

    // MARK: Multi-selection

    func toggleSelection(_ sticker: PlacedSticker) {
        if selectedIDs.contains(sticker.id) { selectedIDs.remove(sticker.id) }
        else { selectedIDs.insert(sticker.id) }
        Haptics.tap()
    }

    func deselectAll() { selectedIDs = [] }
    func setSelection(_ ids: Set<UUID>) { selectedIDs = ids }

    // Group edits — each a single undo step.
    func align(_ edge: AlignEdge) { checkpoint(); collage.align(selectedIDs, edge); Haptics.tap() }
    func groupScale(_ factor: CGFloat) { checkpoint(); collage.scaleSelected(selectedIDs, by: factor) }
    func groupRotate(_ delta: CGFloat) { checkpoint(); collage.rotateSelected(selectedIDs, by: delta) }
    func groupBringToFront() { checkpoint(); collage.bringSelectedToFront(selectedIDs) }
    func groupSendToBack() { checkpoint(); collage.sendSelectedToBack(selectedIDs) }

    func duplicateSelection() {
        checkpoint()
        selectedIDs = collage.duplicateSelected(selectedIDs)
        Haptics.success()
    }

    func deleteSelection() {
        checkpoint()
        collage.removeSelected(selectedIDs)
        selectedIDs = []
    }

    /// Commit a finished group drag (page-space translation) into the elements.
    func commitGroupDrag(_ translation: CGSize, canvas: CGSize) {
        checkpoint()
        for s in collage.selected(selectedIDs) {
            let c = s.center(in: canvas)
            let nc = CGPoint(x: c.x + translation.width, y: c.y + translation.height)
            s.position = CGPoint(x: (nc.x / max(1, canvas.width)).clamped(-0.1, 1.1),
                                 y: (nc.y / max(1, canvas.height)).clamped(-0.1, 1.1))
        }
        groupDrag = .zero
        groupDragging = false
    }

    /// Nudge the selection by a normalized delta (arrow keys on macOS).
    func nudge(dx: CGFloat, dy: CGFloat) {
        guard !selectedIDs.isEmpty else { return }
        checkpoint()
        for s in collage.selected(selectedIDs) {
            s.position = CGPoint(x: (s.position.x + dx).clamped(-0.1, 1.1),
                                 y: (s.position.y + dy).clamped(-0.1, 1.1))
        }
    }

    // MARK: Clipboard (macOS copy/paste)

    func copySelection() {
        clipboard = collage.document.elements.filter { selectedIDs.contains($0.id) }
    }

    func pasteClipboard() {
        guard !clipboard.isEmpty else { return }
        checkpoint()
        var newIDs: Set<UUID> = []
        for var dto in clipboard {
            dto.id = UUID()
            dto.position = CGPoint(x: min(1, dto.position.x + 0.05), y: min(1, dto.position.y + 0.05))
            if let placed = collage.addElement(from: dto) { newIDs.insert(placed.id) }
        }
        selectedIDs = newIDs
        Haptics.success()
    }

    // MARK: Templates & themes

    /// Auto-arrange the elements (the selection if several are selected, else all).
    func applyLayout(_ template: LayoutTemplate) {
        let items = isMultiSelect ? collage.selected(selectedIDs) : collage.ordered
        guard !items.isEmpty else { return }
        checkpoint()
        template.arrange(items, aspect: collage.canvasAspect)
        Haptics.success()
    }

    /// Apply a theme's background + finish in one tap.
    func applyTheme(_ theme: CollageTheme) {
        checkpoint()
        collage.background = theme.background
        collage.backgroundImage = nil
        collage.finish = theme.finish
        Haptics.success()
    }

    // MARK: Canvas format

    /// Change the work-area aspect (undoable). Elements keep their normalized
    /// positions and reflow to the new shape.
    func setCanvasAspect(_ aspect: CGFloat) {
        guard abs(collage.canvasAspect - aspect) > 0.0001 else { return }
        checkpoint()
        collage.canvasAspect = aspect
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

    // MARK: Doodle layer

    /// Enter the freehand doodle editor (checkpoint-before so the whole doodling
    /// session is a single undo step).
    func startDrawing() {
        checkpoint()
        selection = nil
        isDrawing = true
    }

    /// Commit a freehand pencil drawing as a single transformable element placed
    /// exactly where it was drawn, then leave the editor and select it.
    func placeSketch(_ sketch: Sketch, position: CGPoint, scale: CGFloat) {
        let placed = collage.addSketch(sketch, at: position, scale: scale)
        selection = placed
        isDrawing = false
        scheduleAutosave()
        Haptics.success()
    }

    /// Leave the editor without changing the doodle, dropping the checkpoint.
    func cancelDrawing() {
        history.discardLast()
        isDrawing = false
    }

    // MARK: Embellishments

    /// Add a decorative embellishment (shape) and select it.
    func addEmbellishment(_ shape: EmblemShape, colorIndex: Int) {
        checkpoint()
        let placed = collage.addShape(Embellishment(shape: shape, colorIndex: colorIndex))
        selection = placed
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

    // MARK: Cutout styling

    /// Open the filter/outline sheet for a cutout (checkpoint-before so the whole
    /// styling session is a single undo step).
    func editStyle(_ sticker: PlacedSticker) {
        guard !sticker.isText else { return }
        checkpoint()
        selection = sticker
        editingStyle = sticker
    }

    /// Finish styling. On cancel the sheet has already reverted the values, so
    /// drop the no-op checkpoint.
    func finishEditingStyle(cancelled: Bool) {
        defer { editingStyle = nil }
        if cancelled { history.discardLast() }
        scheduleAutosave()
    }

    /// Open the edge-cleanup editor for a cutout (checkpoint-before so the whole
    /// cleanup is one undo step).
    func cleanUp(_ sticker: PlacedSticker) {
        guard sticker.image != nil else { return }
        checkpoint()
        selection = sticker
        cleaningCutout = sticker
    }

    /// Finish cleanup: apply the cleaned image, or drop the checkpoint on cancel.
    func finishCleanup(_ sticker: PlacedSticker, image: PlatformImage?) {
        defer { cleaningCutout = nil }
        if let image { sticker.replaceCutout(image) }
        else { history.discardLast() }   // cancelled — no change
        scheduleAutosave()
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
