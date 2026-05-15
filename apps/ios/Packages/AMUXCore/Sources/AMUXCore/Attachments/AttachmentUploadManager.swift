import Foundation
import SwiftData
import Supabase

/// Manages file uploads to Supabase Storage.
/// Handles progress tracking, state transitions, and error recovery.
///
/// Thread safety: This class is marked `@unchecked Sendable` because:
/// - All `@Model` mutations happen on the main thread via `MainActor.run`
/// - Network I/O happens on background threads
/// - `modelContext` is thread-confined to the main thread
public class AttachmentUploadManager: NSObject, @unchecked Sendable {
    private let modelContext: ModelContext
    private let supabaseClient: SupabaseClient

    public init(modelContext: ModelContext, supabaseClient: SupabaseClient) {
        self.modelContext = modelContext
        self.supabaseClient = supabaseClient
    }

    /// Convenience factory used by AMUXUI (which doesn't depend on the
    /// `Supabase` package directly) to build a manager wired to the project's
    /// configured Supabase instance via `SupabaseProjectConfiguration`.
    public static func fromMainBundle(modelContext: ModelContext) throws -> AttachmentUploadManager {
        let config = try SupabaseProjectConfiguration.fromMainBundle()
        let client = SupabaseClient(supabaseURL: config.url, supabaseKey: config.publishableKey)
        return AttachmentUploadManager(modelContext: modelContext, supabaseClient: client)
    }

    /// Begin uploading a file to Storage.
    /// Returns the AttachmentUpload record created (state=pending initially).
    /// Upload happens in background; caller should observe `uploadState` via SwiftData.
    public func startUpload(
        filePath: URL,
        messageID: String,
        sessionID: String,
        teamID: String
    ) async throws -> AttachmentUpload {
        // Validate file exists and is readable
        let fileData = try Data(contentsOf: filePath)
        let fileSize = fileData.count

        // Validate size ≤ 50MB
        let maxSize: Int64 = 52_428_800
        guard fileSize <= maxSize else {
            throw UploadError.fileTooLarge(size: Int64(fileSize), limit: maxSize)
        }

        // Create record
        let attachmentID = UUID().uuidString.prefix(12).lowercased()
        let fileName = filePath.lastPathComponent
        let upload = AttachmentUpload(
            attachmentID: String(attachmentID),
            messageID: messageID,
            sessionID: sessionID,
            fileName: fileName,
            fileSize: Int64(fileSize)
        )

        // Insert into SwiftData
        modelContext.insert(upload)
        do {
            try modelContext.save()
        } catch {
            print("ERROR: Failed to save AttachmentUpload record: \(error.localizedDescription)")
            throw UploadError.uploadFailed("Failed to create upload record: \(error.localizedDescription)")
        }

        // Start async upload (fire-and-forget with state updates)
        Task {
            await self.performUpload(fileData: fileData, teamID: teamID, uploadID: upload.attachmentID)
        }

        return upload
    }

    /// Perform the actual upload, updating state/storageURL/error as it progresses.
    private func performUpload(fileData: Data, teamID: String, uploadID: String) async {
        // Update to uploading state on main thread
        await MainActor.run {
            if let upload = self.fetchUpload(byID: uploadID) {
                upload.uploadState = .uploading
                upload.uploadedBytes = 0
                do {
                    try self.modelContext.save()
                } catch {
                    print("ERROR: Failed to save uploading state: \(error.localizedDescription)")
                }
            }
        }

        do {
            // Fetch upload details for path construction (must happen on main thread)
            let upload = await MainActor.run { self.fetchUpload(byID: uploadID) }
            guard let upload = upload else {
                return
            }

            let uploadPath = "\(teamID)/\(upload.sessionID)/\(upload.attachmentID)/\(upload.fileName)"

            // Upload to Supabase Storage (off main thread)
            try await supabaseClient.storage
                .from("attachments")
                .upload(
                    uploadPath,
                    data: fileData,
                    options: FileOptions(
                        cacheControl: "3600",
                        contentType: mimeType(for: upload.fileName)
                    )
                )

            // Get public URL
            let publicURL = try supabaseClient.storage
                .from("attachments")
                .getPublicURL(path: uploadPath)

            // Mark complete on main thread
            await MainActor.run {
                if let upload = self.fetchUpload(byID: uploadID) {
                    upload.uploadState = .completed
                    upload.uploadedBytes = upload.fileSize
                    upload.storageURL = publicURL.absoluteString
                    do {
                        try self.modelContext.save()
                    } catch {
                        print("ERROR: Failed to save completed state: \(error.localizedDescription)")
                    }
                }
            }

        } catch {
            // Mark failed on main thread with error message
            await MainActor.run {
                if let upload = self.fetchUpload(byID: uploadID) {
                    upload.uploadState = .failed
                    upload.uploadError = error.localizedDescription
                    do {
                        try self.modelContext.save()
                    } catch {
                        print("ERROR: Failed to save failed state: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    /// Re-fetch an upload record by ID in the current context.
    private func fetchUpload(byID uploadID: String) -> AttachmentUpload? {
        let descriptor = FetchDescriptor<AttachmentUpload>(
            predicate: #Predicate<AttachmentUpload> { $0.attachmentID == uploadID }
        )
        do {
            let uploads = try modelContext.fetch(descriptor)
            return uploads.first
        } catch {
            print("ERROR: Failed to fetch AttachmentUpload: \(error)")
            return nil
        }
    }

    /// Retry a failed upload.
    public func retryUpload(attachmentID: String, filePath: URL, teamID: String) async throws {
        // Re-fetch AttachmentUpload from SwiftData
        let descriptor = FetchDescriptor<AttachmentUpload>(
            predicate: #Predicate<AttachmentUpload> { $0.attachmentID == attachmentID }
        )
        let uploads = try modelContext.fetch(descriptor)
        guard uploads.first != nil else {
            throw UploadError.attachmentNotFound
        }

        let fileData = try Data(contentsOf: filePath)
        await performUpload(fileData: fileData, teamID: teamID, uploadID: attachmentID)
    }
}

public enum UploadError: LocalizedError {
    case fileTooLarge(size: Int64, limit: Int64)
    case attachmentNotFound
    case uploadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .fileTooLarge(let size, let limit):
            return "File size \(size) bytes exceeds limit \(limit) bytes"
        case .attachmentNotFound:
            return "Attachment not found"
        case .uploadFailed(let msg):
            return "Upload failed: \(msg)"
        }
    }
}

// Helper to determine MIME type
private func mimeType(for fileName: String) -> String {
    let ext = (fileName as NSString).pathExtension.lowercased()
    switch ext {
    case "jpg", "jpeg": return "image/jpeg"
    case "png": return "image/png"
    case "gif": return "image/gif"
    case "pdf": return "application/pdf"
    case "txt": return "text/plain"
    case "md": return "text/markdown"
    case "json": return "application/json"
    case "swift": return "text/x-swift"
    case "py": return "text/x-python"
    default: return "application/octet-stream"
    }
}
