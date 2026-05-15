import SwiftUI

public extension MentionTarget {
    enum Kind: Sendable, Equatable, Hashable {
        case member
        case agent
    }
}

/// Lightweight handle for an actor that can be `@`-mentioned in the
/// composer. Carries display name (used both as the matching needle and
/// the rendered token) and the underlying actor id (so the caller can
/// either insert it inline or toggle a routing chip).
public struct MentionTarget: Identifiable, Equatable, Hashable, Sendable {
    public let id: String          // actor id
    public let displayName: String
    public let subtitle: String?   // e.g. "Member", "Claude · idle"
    public let kind: Kind

    public init(id: String,
                displayName: String,
                subtitle: String? = nil,
                kind: Kind = .member) {
        self.id = id
        self.displayName = displayName
        self.subtitle = subtitle
        self.kind = kind
    }
}

/// Inline autocomplete card for `@`-mentions. Shows session humans and
/// agents in a single visually-grouped list. Tapping a row passes the
/// `MentionTarget` back to the parent which decides what to do with it
/// (members → inline `@name` token in the body, agents → add a removable
/// chip above the composer).
public struct MentionsPopup: View {
    let candidates: [MentionTarget]
    let onTap: (MentionTarget) -> Void

    public init(candidates: [MentionTarget],
                onTap: @escaping (MentionTarget) -> Void) {
        self.candidates = candidates
        self.onTap = onTap
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(candidates) { target in
                Button {
                    onTap(target)
                } label: {
                    MentionRow(target: target)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(target.kind == .agent ? "agent \(target.displayName)" : "member \(target.displayName)"))

                if target.id != candidates.last?.id {
                    Divider()
                        .padding(.leading, 56)
                        .opacity(0.4)
                }
            }
        }
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.separator.opacity(0.35), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

private struct MentionRow: View {
    let target: MentionTarget

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 1) {
                Text(target.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let subtitle = target.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(avatarBackground)
                .frame(width: 32, height: 32)
            Image(systemName: target.kind == .agent ? "sparkles" : "person.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(avatarForeground)
        }
    }

    private var avatarBackground: AnyShapeStyle {
        switch target.kind {
        case .member: AnyShapeStyle(Color.secondary.opacity(0.18))
        case .agent:  AnyShapeStyle(Color.orange.opacity(0.22))
        }
    }

    private var avatarForeground: Color {
        switch target.kind {
        case .member: .secondary
        case .agent:  .orange
        }
    }

}

#Preview {
    VStack {
        Spacer()
        MentionsPopup(
            candidates: [
                MentionTarget(id: "1", displayName: "matt", subtitle: "Member", kind: .member),
                MentionTarget(id: "2", displayName: "macmini-simulator", subtitle: "Member", kind: .member),
                MentionTarget(id: "3", displayName: "mini", subtitle: "Claude · idle", kind: .agent),
                MentionTarget(id: "4", displayName: "swarm-1", subtitle: "OpenCode · running", kind: .agent),
            ],
            onTap: { _ in }
        )
        .padding(.horizontal, 16)
        Spacer()
    }
    .background(Color.gray.opacity(0.25))
}
