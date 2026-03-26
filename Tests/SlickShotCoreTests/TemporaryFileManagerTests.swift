import CoreGraphics
import Foundation
import Testing

@testable import SlickShotCore

private extension Data {
    static func pngStub() -> Data {
        Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }
}

struct TemporaryFileManagerTests {
    @Test func writePNG_createsTemporaryFile() throws {
        let directory = try TestDirectory()
        let manager = TemporaryFileManager(rootDirectory: directory.url)
        let recordID = UUID()

        let fileURL = try manager.writePNG(data: .pngStub(), for: recordID)

        #expect(fileURL.pathExtension == "png")
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        #expect(try Data(contentsOf: fileURL) == .pngStub())
    }

    @Test func cleanup_removesTemporaryFile() throws {
        let directory = try TestDirectory()
        let manager = TemporaryFileManager(rootDirectory: directory.url)
        let fileURL = try manager.writePNG(data: .pngStub(), for: UUID())

        manager.cleanup(fileURL)

        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)
    }

    @Test func recoverStaleFiles_removesExistingManagedFiles() throws {
        let directory = try TestDirectory()
        let staleURL = directory.url.appending(path: "stale.png")
        try Data.pngStub().write(to: staleURL)
        let manager = TemporaryFileManager(rootDirectory: directory.url)

        manager.recoverStaleFiles()

        #expect(FileManager.default.fileExists(atPath: staleURL.path) == false)
    }

    @Test func screenshotStore_beginDrag_createsTemporaryFileAndMarksDragging() throws {
        let directory = try TestDirectory()
        let manager = TemporaryFileManager(rootDirectory: directory.url)
        let store = ScreenshotStore(
            now: { Date(timeIntervalSince1970: 1_000) },
            temporaryFileManager: manager
        )
        let id = store.insert(image: .pngStub(), sourceDisplay: "main", selectionRect: .zero)

        let fileURL = try store.beginDrag(id: id)

        let record = try #require(store.record(id: id))
        #expect(record.status == .dragging)
        #expect(record.temporaryBackingURL == fileURL)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func screenshotStore_cancelDrag_removesTemporaryFileAndRestoresPendingState() throws {
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let directory = try TestDirectory()
        let manager = TemporaryFileManager(rootDirectory: directory.url)
        let store = ScreenshotStore(
            now: { currentDate },
            temporaryFileManager: manager
        )
        let id = store.insert(image: .pngStub(), sourceDisplay: "main", selectionRect: .zero)
        let fileURL = try store.beginDrag(id: id)

        currentDate = currentDate.addingTimeInterval(120)
        store.cancelDrag(id: id)

        let record = try #require(store.record(id: id))
        #expect(record.status == .pending)
        #expect(record.temporaryBackingURL == nil)
        #expect(record.expiresAt == currentDate.addingTimeInterval(300))
        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)
    }

    @Test func screenshotStore_markDropped_removesTemporaryFile() throws {
        let directory = try TestDirectory()
        let manager = TemporaryFileManager(rootDirectory: directory.url)
        let store = ScreenshotStore(
            now: { Date(timeIntervalSince1970: 1_000) },
            temporaryFileManager: manager
        )
        let id = store.insert(image: .pngStub(), sourceDisplay: "main", selectionRect: .zero)
        let fileURL = try store.beginDrag(id: id)

        store.markDropped(id: id)

        let record = try #require(store.record(id: id))
        #expect(record.status == .dropped)
        #expect(record.temporaryBackingURL == nil)
        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)
    }

    @Test func screenshotStore_delete_removesTemporaryFile() throws {
        let directory = try TestDirectory()
        let manager = TemporaryFileManager(rootDirectory: directory.url)
        let store = ScreenshotStore(
            now: { Date(timeIntervalSince1970: 1_000) },
            temporaryFileManager: manager
        )
        let id = store.insert(image: .pngStub(), sourceDisplay: "main", selectionRect: .zero)
        let fileURL = try store.beginDrag(id: id)

        store.delete(id: id)

        #expect(store.record(id: id) == nil)
        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)
    }

    @Test func screenshotStore_expire_removesTemporaryFile() throws {
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let directory = try TestDirectory()
        let manager = TemporaryFileManager(rootDirectory: directory.url)
        let store = ScreenshotStore(
            now: { currentDate },
            temporaryFileManager: manager
        )
        let id = store.insert(image: .pngStub(), sourceDisplay: "main", selectionRect: .zero)
        let fileURL = try store.beginDrag(id: id)

        store.cancelDrag(id: id)
        currentDate = currentDate.addingTimeInterval(301)
        store.expire()

        #expect(store.record(id: id) == nil)
        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)
    }

    @Test func screenshotStore_init_recoversStaleTemporaryFiles() throws {
        let directory = try TestDirectory()
        let staleURL = directory.url.appending(path: "stale.png")
        try Data.pngStub().write(to: staleURL)

        _ = ScreenshotStore(
            now: Date.init,
            temporaryFileManager: TemporaryFileManager(rootDirectory: directory.url)
        )

        #expect(FileManager.default.fileExists(atPath: staleURL.path) == false)
    }
}

private struct TestDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
