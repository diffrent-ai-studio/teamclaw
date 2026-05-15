import Foundation

/// Request/response RPC client over the daemon's
/// `device/{deviceID}/rpc/req` and `rpc/res` topic pair.
///
/// `TeamclawService` used to inline this pattern at every call site —
/// build a stream, publish, iterate filtering by `requestID`, time out
/// after 10s. Eleven copies of the same six-step dance accumulated
/// before this refactor, all subtly different in how they handled
/// timeouts and response parsing. `invoke(...)` centralizes the dance
/// so each caller only does request construction and result handling.
///
/// Response routing goes through `MQTTMessageHub.messages(topic:)`, so
/// the awaiter only sees envelopes on the matching `rpc/res` topic —
/// no per-message topic filter inside the for-await loop.
public struct TeamclawRPCClient: Sendable {
    private let mqtt: MQTTService
    private let hub: MQTTMessageHub

    public init(mqtt: MQTTService, hub: MQTTMessageHub) {
        self.mqtt = mqtt
        self.hub = hub
    }

    /// Publish `request` to `device/{targetDeviceID}/rpc/req` for the
    /// given team and await a response with matching `requestID` on the
    /// paired `rpc/res` topic, up to `timeout`. Returns the matched
    /// `Teamclaw_RpcResponse`, or nil on timeout / serialization failure.
    ///
    /// The caller is responsible for stamping `request.requestID` and
    /// `request.method`; this method does not mutate the request.
    public func invoke(
        request: Teamclaw_RpcRequest,
        teamID: String,
        targetDeviceID: String,
        timeout: TimeInterval = 10
    ) async -> Teamclaw_RpcResponse? {
        let reqTopic = MQTTTopics.deviceRpcRequest(teamID: teamID, deviceID: targetDeviceID)
        let resTopic = MQTTTopics.deviceRpcResponse(teamID: teamID, deviceID: targetDeviceID)

        let stream = await hub.messages(topic: resTopic)
        guard let data = try? request.serializedData() else { return nil }
        try? await mqtt.publish(topic: reqTopic, payload: data, retain: false)

        let requestID = request.requestID
        return await withTaskGroup(of: Teamclaw_RpcResponse?.self) { group in
            group.addTask {
                for await msg in stream {
                    if Task.isCancelled { return nil }
                    guard let response = try? Teamclaw_RpcResponse(serializedBytes: msg.payload),
                          response.requestID == requestID else { continue }
                    return response
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
