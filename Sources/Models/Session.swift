import SwiftUI
import Observation

/// App-wide, non-persisted session state: the working collage, the photo
/// currently loaded into the cutout stage, transient busy/toast flags, and the
/// currently-selected placed sticker.
@Observable
@MainActor
final class Session {
    /// The live collage document.
    let collage = Collage()

    /// The photo loaded into the cutout stage (nil until one is imported).
    var stageImage: PlatformImage?

    /// The currently selected placed sticker on the canvas (for the inspector).
    var selection: PlacedSticker?

    /// A cut-out currently in flight (drives spinners / disables controls).
    var isLifting = false

    /// A short-lived toast message shown after actions.
    var toast: String?
    private var toastTask: Task<Void, Never>?

    /// Which top-level tab is showing.
    var tab: Tab = .atelier
    enum Tab: Hashable { case atelier, tiroir }

    /// Load a photo into the cutout stage.
    func loadStage(_ image: PlatformImage) {
        stageImage = image
    }

    /// Load the bundled sample photo.
    func loadSample() {
        if let s = SampleImage.make() { stageImage = s }
    }

    /// Show a toast for ~2 seconds.
    func flash(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if !Task.isCancelled { self?.toast = nil }
        }
    }

    /// Add a lifted cutout to the collage, select it, and switch to the studio.
    @discardableResult
    func placeOnCanvas(_ image: PlatformImage, sourceID: UUID? = nil) -> PlacedSticker {
        let placed = collage.add(image: image, sourceID: sourceID)
        selection = placed
        Haptics.success()
        return placed
    }
}
