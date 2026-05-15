import SwiftUI
import AMUXCore

public struct NewCollabSheet: View {
    let teamclawService: TeamclawService
    let teamId: String
    let targetDeviceID: String
    let peerId: String
    let onCreated: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var summary = ""
    @State private var isSending = false

    public init(
        teamclawService: TeamclawService,
        teamId: String,
        targetDeviceID: String,
        peerId: String,
        onCreated: @escaping (String) -> Void
    ) {
        self.teamclawService = teamclawService
        self.teamId = teamId
        self.targetDeviceID = targetDeviceID
        self.peerId = peerId
        self.onCreated = onCreated
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    TextField("Title", text: $title)
                    TextField("Summary (optional)", text: $summary, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("New Collab Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { createSession() } label: {
                        Text("Create")
                            .font(.subheadline).fontWeight(.medium)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .liquidGlass(in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                    .opacity(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending ? 0.4 : 1)
                }
            }
        }
    }

    private func createSession() {
        guard let mqtt = teamclawService.mqttRef else { return }
        isSending = true

        let createReq = teamclawService.makeCreateSessionRequest(
            teamId: teamId,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        guard !targetDeviceID.isEmpty else {
            isSending = false
            return
        }
        var rpcReq = Teamclaw_RpcRequest()
        rpcReq.requestID = String(UUID().uuidString.prefix(8).lowercased())
        rpcReq.senderDeviceID = targetDeviceID
        rpcReq.method = .createSession(createReq)

        let topic = MQTTTopics.deviceRpcRequest(teamID: teamId, deviceID: targetDeviceID)
        if let data = try? rpcReq.serializedData() {
            Task {
                try? await mqtt.publish(topic: topic, payload: data, retain: false)
            }
        }

        dismiss()
    }
}
