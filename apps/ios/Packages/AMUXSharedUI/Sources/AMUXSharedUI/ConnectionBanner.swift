import SwiftUI
import AMUXCore

/// Stateless top-edge banner that reflects MQTT transport state only.
/// Hosted by platform shells (iOS `ConnectionBannerOverlay`, Mac
/// `MainWindowView`). `.hidden` collapses the banner to `EmptyView`.
public struct ConnectionBanner: View {
    public enum State: Equatable {
        case hidden
        case reconnecting
        case disconnected
    }

    let state: State
    let onReconnect: (() -> Void)?

    public init(state: State, onReconnect: (() -> Void)? = nil) {
        self.state = state
        self.onReconnect = onReconnect
    }

    public var body: some View {
        switch state {
        case .hidden:
            EmptyView()
        case .reconnecting:
            banner(icon: "arrow.triangle.2.circlepath", text: "Reconnecting\u{2026}", color: .yellow)
        case .disconnected:
            Button { onReconnect?() } label: {
                banner(icon: "bolt.slash.fill", text: "Not Connected \u{00B7} Click to reconnect", color: .red)
            }
            .buttonStyle(.plain)
        }
    }

    private func banner(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(text).font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .foregroundStyle(.white)
        .background(color, in: Capsule())
        .padding(.top, 10)
    }
}

public extension ConnectionBanner.State {
    /// Maps MQTT transport state into a banner state. Nothing is shown when
    /// we're fully connected — agent availability is surfaced via the Actors
    /// tab and Settings, not this banner.
    static func from(connectionState: ConnectionState) -> Self {
        switch connectionState {
        case .reconnecting, .connecting: return .reconnecting
        case .disconnected: return .disconnected
        case .connected: return .hidden
        }
    }
}
