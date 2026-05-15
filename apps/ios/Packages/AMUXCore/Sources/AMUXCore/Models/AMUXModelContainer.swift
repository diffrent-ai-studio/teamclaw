import Foundation
import SwiftData

public enum AMUXModelContainerFactory {
    public static func make() throws -> ModelContainer {
        let schema = Schema(versionedSchema: AMUXSchemaV1.self)
        let storeURL = try persistentStoreURL()
        let config = ModelConfiguration(schema: schema, url: storeURL)

        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            // The local SwiftData store is only a cache of daemon-backed state.
            // If migration fails, drop the cache and let the app repopulate it
            // instead of crashing at launch.
            try removeStoreFiles(at: storeURL)
            return try ModelContainer(for: schema, configurations: config)
        }
    }

    private static func persistentStoreURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let bundleID = Bundle.main.bundleIdentifier ?? "tech.teamclaw.amux"
        let directory = appSupport.appendingPathComponent(bundleID, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("amux.store")
    }

    private static func removeStoreFiles(at url: URL) throws {
        let fm = FileManager.default
        let candidates = [
            url,
            url.appendingPathExtension("shm"),
            url.appendingPathExtension("wal"),
        ]
        for candidate in candidates where fm.fileExists(atPath: candidate.path) {
            try fm.removeItem(at: candidate)
        }
    }
}
