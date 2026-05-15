import SwiftUI
import PhotosUI
import AMUXCore

struct AttachmentDrawerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Binding var attachments: [URL]
    @Binding var selectedModelId: String?
    let runtime: Runtime?
    let uploadManager: AttachmentUploadManager?
    let sessionID: String
    let teamID: String
    let onUploadStarted: (String, AttachmentUpload) -> Void

    @State private var showFilePicker = false
    @State private var showCamera = false
    @State private var photoItems: [PhotosPickerItem] = []

    var body: some View {
        NavigationStack {
            List {
                Section("Attach") {
                    Button { showFilePicker = true } label: {
                        Label("Files", systemImage: "doc")
                    }
                    Button { showCamera = true } label: {
                        Label("Camera", systemImage: "camera")
                    }
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 5, matching: .images) {
                        Label("Photos", systemImage: "photo.on.rectangle")
                    }
                }

                if let runtime, !runtime.availableModels.isEmpty {
                    Section("Model") {
                        ForEach(runtime.availableModels) { model in
                            Button {
                                selectedModelId = model.id
                            } label: {
                                HStack {
                                    Text(model.displayName)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if model.id == resolvedSelection(runtime: runtime) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Attachments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    Task {
                        for url in urls where !attachments.contains(url) {
                            attachments.append(url)

                            // Trigger upload if manager available
                            if let uploadManager = uploadManager {
                                do {
                                    let upload = try await uploadManager.startUpload(
                                        filePath: url,
                                        messageID: UUID().uuidString,
                                        sessionID: sessionID,
                                        teamID: teamID
                                    )
                                    onUploadStarted(url.absoluteString, upload)
                                } catch {
                                    print("Upload failed: \(error)")
                                }
                            }
                        }
                        dismiss()
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraImagePicker(
                    onCapture: { url in
                        Task {
                            attachments.append(url)

                            // Trigger upload if manager available
                            if let uploadManager = uploadManager {
                                do {
                                    let upload = try await uploadManager.startUpload(
                                        filePath: url,
                                        messageID: UUID().uuidString,
                                        sessionID: sessionID,
                                        teamID: teamID
                                    )
                                    onUploadStarted(url.absoluteString, upload)
                                } catch {
                                    print("Upload failed: \(error)")
                                }
                            }
                            showCamera = false
                            dismiss()
                        }
                    },
                    onCancel: { showCamera = false }
                )
                .ignoresSafeArea()
            }
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            let url = FileManager.default.temporaryDirectory
                                .appendingPathComponent("photo-\(UUID().uuidString).jpg")
                            try? data.write(to: url)
                            await MainActor.run { attachments.append(url) }

                            // Trigger upload
                            if let uploadManager = uploadManager {
                                Task {
                                    do {
                                        let upload = try await uploadManager.startUpload(
                                            filePath: url,
                                            messageID: UUID().uuidString,
                                            sessionID: sessionID,
                                            teamID: teamID
                                        )
                                        onUploadStarted(url.absoluteString, upload)
                                    } catch {
                                        print("Upload failed: \(error)")
                                    }
                                }
                            }
                        }
                    }
                    await MainActor.run {
                        photoItems = []
                        dismiss()
                    }
                }
            }
        }
    }

    private func resolvedSelection(runtime: Runtime) -> String? {
        if let selectedModelId, !selectedModelId.isEmpty { return selectedModelId }
        if let current = runtime.currentModel, !current.isEmpty { return current }
        return nil
    }
}
