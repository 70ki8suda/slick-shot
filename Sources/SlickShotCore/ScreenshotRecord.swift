import Foundation
import CoreGraphics

public enum ScreenshotStatus: Equatable {
    case pending
    case dragging
    case dropped
}

public struct ScreenshotRecord: Identifiable, Equatable {
    public let id: UUID
    public let createdAt: Date
    public var expiresAt: Date
    public var status: ScreenshotStatus
    public let imageRepresentation: Data
    public let displayThumbnailRepresentation: Data
    public let sourceDisplay: String
    public let selectionRect: CGRect
    public var temporaryBackingURL: URL?

    public init(
        id: UUID,
        createdAt: Date,
        expiresAt: Date,
        status: ScreenshotStatus,
        imageRepresentation: Data,
        displayThumbnailRepresentation: Data,
        sourceDisplay: String,
        selectionRect: CGRect,
        temporaryBackingURL: URL? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.status = status
        self.imageRepresentation = imageRepresentation
        self.displayThumbnailRepresentation = displayThumbnailRepresentation
        self.sourceDisplay = sourceDisplay
        self.selectionRect = selectionRect
        self.temporaryBackingURL = temporaryBackingURL
    }
}
