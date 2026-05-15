import Foundation

public enum MQTTTopics {
    public static func normalizedTeamID(_ teamID: String) -> String {
        teamID.isEmpty ? "teamclaw" : teamID
    }

    public static func deviceBase(teamID: String, deviceID: String) -> String {
        "amux/\(normalizedTeamID(teamID))/device/\(deviceID)"
    }

    public static func teamclawBase(teamID: String) -> String {
        "amux/\(normalizedTeamID(teamID))"
    }

    /// Fixed device-scoped request channel for the MQTT rearchitecture.
    public static func deviceRpcRequest(teamID: String, deviceID: String) -> String {
        "\(deviceBase(teamID: teamID, deviceID: deviceID))/rpc/req"
    }

    /// Fixed device-scoped response channel for the MQTT rearchitecture.
    public static func deviceRpcResponse(teamID: String, deviceID: String) -> String {
        "\(deviceBase(teamID: teamID, deviceID: deviceID))/rpc/res"
    }

    /// Targeted device notification channel used to invalidate local state.
    public static func deviceNotify(teamID: String, deviceID: String) -> String {
        "\(deviceBase(teamID: teamID, deviceID: deviceID))/notify"
    }

    /// Single realtime stream for live session events in the new contract.
    public static func sessionLive(teamID: String, sessionID: String) -> String {
        "\(teamclawBase(teamID: teamID))/session/\(sessionID)/live"
    }

    // ─── Phase 2 — new-architecture paths (dual-published by daemon since Phase 1a) ───

    /// New device-scoped retained state topic. LWT migrates here in Phase 3;
    /// until then Phase 1a daemon mirror-publishes normal transitions here and
    /// keeps LWT firing on /status. ConnectionMonitor dual-subscribes.
    public static func deviceState(teamID: String, deviceID: String) -> String {
        "\(deviceBase(teamID: teamID, deviceID: deviceID))/state"
    }

    /// Per-runtime retained state. Payload is the same `Amux_RuntimeInfo` that
    /// `agentState(...)` carries — only the wire path differs.
    public static func runtimeState(teamID: String, deviceID: String, runtimeID: String) -> String {
        "\(deviceBase(teamID: teamID, deviceID: deviceID))/runtime/\(runtimeID)/state"
    }

    public static func runtimeStateWildcard(teamID: String, deviceID: String) -> String {
        "\(deviceBase(teamID: teamID, deviceID: deviceID))/runtime/+/state"
    }

    public static func runtimeStatePrefix(teamID: String, deviceID: String) -> String {
        "\(deviceBase(teamID: teamID, deviceID: deviceID))/runtime/"
    }

    public static func runtimeCommands(teamID: String, deviceID: String, runtimeID: String) -> String {
        "\(deviceBase(teamID: teamID, deviceID: deviceID))/runtime/\(runtimeID)/commands"
    }

    public static func runtimeCommandsWildcard(teamID: String, deviceID: String) -> String {
        "\(deviceBase(teamID: teamID, deviceID: deviceID))/runtime/+/commands"
    }

    /// Team-scoped user notify channel. Requires broker JWT auth before use
    /// (Phase 1d prerequisite); builder is available now so Phase 2 code can
    /// reference it, but no subscribe happens until 1d ships.
    public static func userNotify(teamID: String, actorID: String) -> String {
        "\(teamclawBase(teamID: teamID))/user/\(actorID)/notify"
    }
}
