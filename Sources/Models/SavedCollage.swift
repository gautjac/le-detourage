import Foundation
import SwiftData

/// A collage the user has saved to the gallery ("les Pages"). Stores a small
/// preview thumbnail plus the full, self-contained document blob so it can be
/// reopened exactly, even if the source drawer cutouts are long gone.
@Model
final class SavedCollage {
    /// Stable identifier, also used to tie the autosave draft to its gallery row.
    var id: UUID
    /// User-facing name (editable in the gallery).
    var title: String
    var createdAt: Date
    var updatedAt: Date
    /// A small PNG preview for the gallery grid.
    @Attribute(.externalStorage) var thumbnailData: Data
    /// The encoded `CollageDocument` (JSON) — the whole restorable collage.
    @Attribute(.externalStorage) var documentData: Data

    init(id: UUID = UUID(),
         title: String,
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         thumbnailData: Data,
         documentData: Data) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.thumbnailData = thumbnailData
        self.documentData = documentData
    }

    /// Decode the stored document, or an empty document if the blob is corrupt.
    var document: CollageDocument {
        (try? JSONDecoder().decode(CollageDocument.self, from: documentData)) ?? CollageDocument()
    }
}
