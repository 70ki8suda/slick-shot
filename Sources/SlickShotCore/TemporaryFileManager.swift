import Foundation

public protocol TemporaryFileManaging: AnyObject {
    func writePNG(data: Data, for id: UUID) throws -> URL
    func cleanup(_ url: URL)
    func recoverStaleFiles()
}

public final class TemporaryFileManager: TemporaryFileManaging {
    public let rootDirectory: URL

    private let fileManager: FileManager

    public init(
        rootDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.rootDirectory = rootDirectory ?? fileManager.temporaryDirectory.appending(
            path: "slick-shot-drag",
            directoryHint: .isDirectory
        )
    }

    public func writePNG(data: Data, for id: UUID) throws -> URL {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let fileURL = rootDirectory.appending(path: "\(id.uuidString).png")
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    public func cleanup(_ url: URL) {
        try? fileManager.removeItem(at: url)
    }

    public func recoverStaleFiles() {
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for fileURL in fileURLs {
            try? fileManager.removeItem(at: fileURL)
        }
    }
}
