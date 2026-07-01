import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
import Photos
#else
import AppKit
#endif

/// Cross-platform PNG export: a save/share flow that lands the bytes wherever
/// the platform expects. On iOS this presents a share sheet (and offers Save to
/// Photos); on macOS a save panel writes to a user-chosen path.
enum Exporter {

    /// Present a share/save flow for the given PNG image with a suggested name.
    @MainActor
    static func exportPNG(_ image: PlatformImage, suggestedName: String) {
        guard let data = image.pngData else { return }
        #if os(iOS)
        shareOnIOS(data: data, suggestedName: suggestedName)
        #else
        saveOnMac(data: data, suggestedName: suggestedName)
        #endif
    }

    #if os(iOS)
    @MainActor
    private static func shareOnIOS(data: Data, suggestedName: String) {
        // Write to a temp file so the share sheet offers a proper filename.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(suggestedName)
            .appendingPathExtension("png")
        do { try data.write(to: url, options: .atomic) } catch { return }

        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first,
              let root = scene.keyWindow?.rootViewController else { return }

        // Present from the top-most controller.
        var top = root
        while let presented = top.presentedViewController { top = presented }

        // iPad popover anchoring.
        if let pop = activity.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY,
                                    width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        top.present(activity, animated: true)
    }
    #else
    @MainActor
    private static func saveOnMac(data: Data, suggestedName: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(suggestedName).png"
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
    #endif
}

#if os(iOS)
private extension UIWindowScene {
    var keyWindow: UIWindow? {
        windows.first { $0.isKeyWindow } ?? windows.first
    }
}
#endif
