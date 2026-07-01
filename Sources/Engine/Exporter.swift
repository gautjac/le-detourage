import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
import Photos
#else
import AppKit
#endif

/// Cross-platform PNG output. `save` writes the bytes to a user-chosen location
/// (a save panel on macOS, the share sheet's Save options on iOS); `share`
/// hands the image to the system share sheet — the macOS `NSSharingServicePicker`
/// (AirDrop, Messages, Mail, Notes…) or the iOS `UIActivityViewController`.
enum Exporter {

    /// Save the image to a file the user picks.
    @MainActor
    static func save(_ image: PlatformImage, suggestedName: String) {
        guard let data = image.pngData else { return }
        #if os(iOS)
        presentShareSheet(data: data, suggestedName: suggestedName)
        #else
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(suggestedName).png"
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url, options: .atomic)
        }
        #endif
    }

    /// Present the system share sheet for the image.
    @MainActor
    static func share(_ image: PlatformImage, suggestedName: String) {
        guard let data = image.pngData else { return }
        presentShareSheet(data: data, suggestedName: suggestedName)
    }

    /// Back-compat alias — the collage/sticker save flow.
    @MainActor
    static func exportPNG(_ image: PlatformImage, suggestedName: String) {
        save(image, suggestedName: suggestedName)
    }

    /// Write the PNG to a temp file (so services get a real, named file that
    /// AirDrop / Mail / Messages can attach) and present the share sheet.
    @MainActor
    private static func presentShareSheet(data: Data, suggestedName: String) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(suggestedName)
            .appendingPathExtension("png")
        do { try data.write(to: url, options: .atomic) } catch { return }

        #if os(iOS)
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first,
              let root = scene.keyWindow?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        if let pop = activity.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        top.present(activity, animated: true)
        #else
        let picker = NSSharingServicePicker(items: [url])
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let view = window.contentView else { return }
        let anchor = NSRect(x: view.bounds.midX - 1, y: view.bounds.midY, width: 2, height: 2)
        picker.show(relativeTo: anchor, of: view, preferredEdge: .minY)
        #endif
    }
}

#if os(iOS)
private extension UIWindowScene {
    var keyWindow: UIWindow? {
        windows.first { $0.isKeyWindow } ?? windows.first
    }
}
#endif
