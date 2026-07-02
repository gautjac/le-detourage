import UIKit
import Messages

/// The iMessage sticker browser: presents the user's lifted cutouts (mirrored to
/// the shared App Group container by the main app) as sendable stickers.
final class StickerBrowserViewController: MSStickerBrowserViewController {
    private var stickers: [MSSticker] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        stickerBrowserView.backgroundColor = .clear
        loadStickers()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadStickers()
        stickerBrowserView.reloadData()
    }

    private func loadStickers() {
        stickers = []
        guard let dir = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.jac.LeDetourage")?
            .appendingPathComponent("Stickers", isDirectory: true) else { return }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for url in urls where url.pathExtension.lowercased() == "png" {
            if let sticker = try? MSSticker(contentsOfFileURL: url, localizedDescription: "Cutout") {
                stickers.append(sticker)
            }
        }
    }

    override func numberOfStickers(in stickerBrowserView: MSStickerBrowserView) -> Int {
        stickers.count
    }

    override func stickerBrowserView(_ stickerBrowserView: MSStickerBrowserView,
                                     stickerAt index: Int) -> MSSticker {
        stickers[index]
    }
}
