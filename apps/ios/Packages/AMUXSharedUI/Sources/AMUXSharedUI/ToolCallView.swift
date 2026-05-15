import SwiftUI
import AMUXCore

// MARK: - ToolIcons

/// Shared icon + short-name mapping reused by ToolCallView and CompactToolLine
/// to keep the visual language consistent across platforms.
public enum ToolIcons {
    public static func icon(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("write") || n.contains("edit") { return "doc.text" }
        if n.contains("read") { return "doc" }
        if n.contains("bash") || n.contains("shell") || n.contains("terminal") { return "terminal" }
        if n.contains("search") || n.contains("grep") || n.contains("glob") { return "magnifyingglass" }
        if n.contains("idea") || n.contains("task") { return "lightbulb" }
        if n.contains("web") { return "globe" }
        return "wrench"
    }

    public static func shortName(for name: String) -> String {
        if let range = name.range(of: "__", options: .backwards) {
            return String(name[range.upperBound...].prefix(30))
        }
        return String(name.prefix(30))
    }
}

// MARK: - ToolCallView

public struct ToolCallView: View {
    public let toolName: String
    public let toolId: String
    public let description: String
    public let status: String
    @State private var isExpanded = false

    private var hasDetails: Bool {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != "{}" && trimmed != "null"
    }

    public init(toolName: String, toolId: String, description: String, status: String) {
        self.toolName = toolName
        self.toolId = toolId
        self.description = description
        self.status = status
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if hasDetails { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }
            } label: {
                HStack(spacing: 6) {
                    if hasDetails {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .foregroundStyle(.secondary)
                    }

                    Image(systemName: ToolIcons.icon(for: toolName))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(ToolIcons.shortName(for: toolName.isEmpty ? toolId : toolName))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if hasDetails && !isExpanded {
                        Text(description)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    statusIndicator
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded && hasDetails {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Details")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(description)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 4))
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch status {
        case "running":
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 14, height: 14)
        case "completed":
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(Color.amux.sage)
        case "failed":
            Image(systemName: "xmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(Color.amux.cinnabarDeep)
        default:
            EmptyView()
        }
    }
}

// MARK: - CompactToolLine

public struct CompactToolLine: View {
    public let event: AgentEvent
    @State private var showDetail = false

    private var toolName: String { event.toolName ?? "" }
    private var description: String { event.text ?? "" }
    private var succeeded: Bool { event.success != false }

    private var hasDetails: Bool {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != "{}" && trimmed != "null"
    }

    public init(event: AgentEvent) {
        self.event = event
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: succeeded ? "checkmark" : "xmark")
                    .font(.system(size: 9))
                    .foregroundStyle(succeeded ? .green : .red)

                Image(systemName: ToolIcons.icon(for: toolName))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Text(ToolIcons.shortName(for: toolName.isEmpty ? (event.toolId ?? "") : toolName))
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 1)
            .contentShape(Rectangle())
            .onTapGesture {
                if hasDetails {
                    withAnimation(.easeInOut(duration: 0.15)) { showDetail.toggle() }
                }
            }

            if showDetail && hasDetails {
                Text(description)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - ToolRunSummaryBar

public struct ToolRunSummaryBar: View {
    public let events: [AgentEvent]
    @State private var isExpanded = false

    private var count: Int { events.count }

    private var hasFailure: Bool {
        events.contains { $0.success == false }
    }

    public init(events: [AgentEvent]) {
        self.events = events
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(.secondary)

                    Image(systemName: "wrench")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\(count) tools completed")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    Spacer()

                    if hasFailure {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.amux.cinnabar)
                    }
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.amux.sage)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(events, id: \.id) { event in
                        CompactToolLine(event: event)
                    }
                }
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Event Grouping

// GroupedEvent and groupEvents live in AMUXCore so SessionDetailViewModel
// can maintain a cached grouping that updates only when events change,
// avoiding an O(n) regroup on every body recompute (streaming deltas
// previously forced a regroup on every frame).
