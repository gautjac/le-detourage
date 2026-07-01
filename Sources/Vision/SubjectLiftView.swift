import SwiftUI
import VisionKit

/// A coordinator handle the SwiftUI layer holds to drive the platform lift host.
/// It exposes an async "lift whatever subjects VisionKit found" call and a
/// binding-free callback for when the user taps a subject directly.
@MainActor
final class SubjectLiftController: ObservableObject {
    /// Called with a freshly lifted, transparent cutout.
    var onLift: ((PlatformImage) -> Void)?
    /// Whether VisionKit reports any interactive subjects for the current image
    /// (drives the "Lift the subject" button's enabled state on iOS).
    @Published var hasInteractiveSubjects = false

    /// Set by the representable so the SwiftUI toolbar can trigger a lift of the
    /// most-prominent subject(s) without a tap.
    var liftAllSubjects: (() async -> PlatformImage?)?
}

#if os(iOS)
import UIKit

/// iOS/iPadOS host: an image view with `ImageAnalysisInteraction` configured for
/// `.imageSubject`, so the system's press-and-lift affordance is live. A tap on
/// a subject lifts it; the toolbar can also lift all detected subjects at once.
@available(iOS 17.0, *)
struct SubjectLiftView: UIViewRepresentable {
    let image: PlatformImage
    @ObservedObject var controller: SubjectLiftController

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeUIView(context: Context) -> UIView {
        let container = TapImageView()
        container.backgroundColor = .clear
        container.imageView.image = image
        container.imageView.contentMode = .scaleAspectFit
        container.imageView.isUserInteractionEnabled = true

        let interaction = ImageAnalysisInteraction()
        interaction.preferredInteractionTypes = [.imageSubject]
        interaction.delegate = context.coordinator
        container.imageView.addInteraction(interaction)
        context.coordinator.interaction = interaction
        context.coordinator.container = container

        // Wire the "lift all" hook.
        controller.liftAllSubjects = { [weak coordinator = context.coordinator] in
            await coordinator?.liftAllSubjects()
        }

        // Tap → lift the subject under the finger.
        container.onTap = { [weak coordinator = context.coordinator] point in
            Task { await coordinator?.liftSubject(at: point) }
        }

        context.coordinator.analyze(image: image)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let container = uiView as? TapImageView else { return }
        if container.imageView.image !== image {
            container.imageView.image = image
            context.coordinator.analyze(image: image)
        }
    }

    @MainActor
    final class Coordinator: NSObject, ImageAnalysisInteractionDelegate {
        let controller: SubjectLiftController
        var interaction: ImageAnalysisInteraction?
        weak var container: TapImageView?
        private let analyzer = ImageAnalyzer()

        init(controller: SubjectLiftController) {
            self.controller = controller
        }

        func analyze(image: PlatformImage) {
            controller.hasInteractiveSubjects = false
            Task {
                // Build the config inside the task so it isn't sent across an
                // actor boundary.
                let config = ImageAnalyzer.Configuration([.visualLookUp])
                guard let analysis = try? await analyzer.analyze(image, configuration: config) else {
                    return
                }
                interaction?.analysis = analysis
                interaction?.preferredInteractionTypes = [.imageSubject]
                let subjects = await interaction?.subjects ?? []
                controller.hasInteractiveSubjects = !subjects.isEmpty
            }
        }

        /// Lift the subject at a point in the image view's coordinate space.
        func liftSubject(at point: CGPoint) async {
            guard let interaction else { return }
            // Convert the tap into the subject there, if any.
            if let subject = await interaction.subject(at: point) {
                if let img = try? await interaction.image(for: [subject]) {
                    deliver(img)
                    return
                }
            }
            // No subject under the finger — fall back to lifting everything.
            if let all = await liftAllSubjects() { deliver(all) }
        }

        /// Lift all detected subjects composited into one cutout.
        func liftAllSubjects() async -> PlatformImage? {
            guard let interaction else { return nil }
            let subjects = await interaction.subjects
            guard !subjects.isEmpty else { return nil }
            return try? await interaction.image(for: subjects)
        }

        private func deliver(_ image: PlatformImage) {
            let tight = SubjectMasker.trimTransparentMargins(image)
            controller.onLift?(tight)
        }
    }
}

/// A UIView that centers an image view and reports taps in the image's own
/// coordinate space (accounting for aspect-fit letterboxing).
final class TapImageView: UIView {
    let imageView = UIImageView()
    var onTap: ((CGPoint) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(imageView)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
    }

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        let p = g.location(in: imageView)
        onTap?(p)
    }
}
#endif

#if os(macOS)
import AppKit

/// macOS host: `ImageAnalysisOverlayView` layered over an image view with the
/// subject interaction enabled, so clicking a subject lifts it. The toolbar can
/// also lift all detected subjects at once.
@available(macOS 14.0, *)
struct SubjectLiftView: NSViewRepresentable {
    let image: PlatformImage
    @ObservedObject var controller: SubjectLiftController

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeNSView(context: Context) -> NSView {
        let container = ClickImageView()
        container.wantsLayer = true
        container.imageView.image = image
        container.imageView.imageScaling = .scaleProportionallyUpOrDown

        let overlay = ImageAnalysisOverlayView()
        overlay.autoresizingMask = [.width, .height]
        overlay.frame = container.bounds
        overlay.preferredInteractionTypes = [.imageSubject]
        overlay.trackingImageView = container.imageView
        container.addSubview(overlay)
        context.coordinator.overlay = overlay
        context.coordinator.container = container

        controller.liftAllSubjects = { [weak coordinator = context.coordinator] in
            await coordinator?.liftAllSubjects()
        }

        container.onClick = { [weak coordinator = context.coordinator] point in
            Task { await coordinator?.liftSubject(at: point) }
        }

        context.coordinator.analyze(image: image)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let container = nsView as? ClickImageView else { return }
        if container.imageView.image !== image {
            container.imageView.image = image
            context.coordinator.analyze(image: image)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        let controller: SubjectLiftController
        var overlay: ImageAnalysisOverlayView?
        weak var container: ClickImageView?
        private let analyzer = ImageAnalyzer()

        init(controller: SubjectLiftController) {
            self.controller = controller
        }

        func analyze(image: PlatformImage) {
            controller.hasInteractiveSubjects = false
            Task {
                // The config is built inside the task so it isn't sent across an
                // actor boundary. On macOS the analyzer needs an explicit
                // orientation for an NSImage.
                let config = ImageAnalyzer.Configuration([.visualLookUp])
                guard let analysis = try? await analyzer.analyze(
                    image, orientation: .up, configuration: config) else {
                    return
                }
                overlay?.analysis = analysis
                overlay?.preferredInteractionTypes = [.imageSubject]
                let subjects = await overlay?.subjects ?? []
                controller.hasInteractiveSubjects = !subjects.isEmpty
            }
        }

        func liftSubject(at point: CGPoint) async {
            guard let overlay else { return }
            if let subject = await overlay.subject(at: point) {
                if let img = try? await overlay.image(for: [subject]) {
                    deliver(img); return
                }
            }
            if let all = await liftAllSubjects() { deliver(all) }
        }

        func liftAllSubjects() async -> PlatformImage? {
            guard let overlay else { return nil }
            let subjects = await overlay.subjects
            guard !subjects.isEmpty else { return nil }
            return try? await overlay.image(for: subjects)
        }

        private func deliver(_ image: PlatformImage) {
            let tight = SubjectMasker.trimTransparentMargins(image)
            controller.onLift?(tight)
        }
    }
}

/// An NSView hosting a centered image view that reports clicks in the image
/// view's coordinate space.
final class ClickImageView: NSView {
    let imageView = NSImageView()
    var onClick: ((CGPoint) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageView.autoresizingMask = [.width, .height]
        addSubview(imageView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        imageView.frame = bounds
    }

    override func mouseDown(with event: NSEvent) {
        let p = imageView.convert(event.locationInWindow, from: nil)
        // Flip to a top-left origin to match VisionKit's expectation on macOS.
        let flipped = CGPoint(x: p.x, y: imageView.bounds.height - p.y)
        onClick?(flipped)
    }
}
#endif
