import Foundation

public struct PairingCredentials: Equatable, Sendable {
    public var brokerHost: String
    public var brokerPort: Int
    public var useTLS: Bool
    public var authToken: String

    public init(
        brokerHost: String,
        brokerPort: Int,
        useTLS: Bool,
        authToken: String
    ) {
        self.brokerHost = brokerHost
        self.brokerPort = brokerPort
        self.useTLS = useTLS
        self.authToken = authToken
    }
}

public protocol CredentialStore: AnyObject, Sendable {
    func save(_ credentials: PairingCredentials) throws
    func load() throws -> PairingCredentials?
    func clear() throws
}

// @unchecked Sendable is safe: UserDefaults is documented as thread-safe by Apple.
public final class UserDefaultsCredentialStore: CredentialStore, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func save(_ c: PairingCredentials) throws {
        defaults.set(c.brokerHost, forKey: Keys.brokerHost)
        defaults.set(c.brokerPort, forKey: Keys.brokerPort)
        defaults.set(c.authToken, forKey: Keys.authToken)
        defaults.set(c.useTLS, forKey: Keys.useTLS)
    }

    public func load() throws -> PairingCredentials? {
        guard let host = defaults.string(forKey: Keys.brokerHost),
              !host.isEmpty else {
            return nil
        }
        var port = defaults.integer(forKey: Keys.brokerPort)
        if port == 0 { port = 8883 }
        return PairingCredentials(
            brokerHost: host,
            brokerPort: port,
            useTLS: defaults.bool(forKey: Keys.useTLS),
            authToken: defaults.string(forKey: Keys.authToken) ?? ""
        )
    }

    public func clear() throws {
        for key in Keys.all { defaults.removeObject(forKey: key) }
        // Also remove the legacy device-id key written by older builds, so a
        // clean unpair doesn't leave stale routing state on disk.
        defaults.removeObject(forKey: "amux_device_id")
    }

    private enum Keys {
        static let brokerHost = "amux_broker_host"
        static let brokerPort = "amux_broker_port"
        static let authToken  = "amux_auth_token"
        static let useTLS     = "amux_use_tls"
        static let all = [brokerHost, brokerPort, authToken, useTLS]
    }
}
