import SwiftUI
import AMUXCore

/// Inline autocomplete popup for ACP slash commands. Rendered by the
/// composer whenever the user's in-progress text matches `/<prefix>`
/// and at least one known command starts with that prefix.
///
/// Stateless: the parent owns `candidates` and the `onTap` handler that
/// inserts `/<name> ` into the composer.
public struct SlashCommandsPopup: View {
    let candidates: [SlashCommand]
    let onTap: (SlashCommand) -> Void

    public init(candidates: [SlashCommand], onTap: @escaping (SlashCommand) -> Void) {
        self.candidates = candidates
        self.onTap = onTap
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(candidates) { cmd in
                    Button {
                        onTap(cmd)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("/\(cmd.name)")
                                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(cmd.description)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(minHeight: 34)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text("slash \(cmd.name). \(cmd.description)"))
                    .accessibilityHint(Text("Inserts this command into the message"))

                    if cmd.id != candidates.last?.id {
                        Divider().padding(.leading, 12)
                    }
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: 200)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

#Preview {
    SlashCommandsPopup(
        candidates: [
            SlashCommand(name: "clear", description: "Clear conversation history", inputHint: ""),
            SlashCommand(name: "compact", description: "Compact the context window", inputHint: ""),
            SlashCommand(name: "rename", description: "Rename this session", inputHint: "new name"),
        ],
        onTap: { _ in }
    )
    .padding()
}
