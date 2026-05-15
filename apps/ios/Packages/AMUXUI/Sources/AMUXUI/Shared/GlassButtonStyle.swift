import SwiftUI

extension View {
    /// Liquid-glass prominent button style on iOS 26+, `.borderedProminent` fallback below.
    @ViewBuilder
    public func glassProminentButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    /// Liquid-glass button style on iOS 26+, `.bordered` fallback below.
    @ViewBuilder
    public func glassButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}
