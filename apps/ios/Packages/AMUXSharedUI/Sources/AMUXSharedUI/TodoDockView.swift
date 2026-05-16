import SwiftUI

// MARK: - Public types

public enum TodoItemStatus: Sendable, Equatable {
    case pending
    case inProgress
    case completed
    case cancelled
}

public struct TodoItem: Sendable, Equatable {
    public let content: String
    public let status: TodoItemStatus

    public init(content: String, status: TodoItemStatus) {
        self.content = content
        self.status = status
    }
}

// MARK: - Parser

/// Parse the daemon's todo_update text payload into structured items.
/// Each non-empty line maps to one `TodoItem`. Recognized prefixes:
///   - `[done] foo`       → .completed
///   - `[wip] foo`        → .inProgress
///   - `[todo] foo`       → .pending
///   - `[cancelled] foo`  → .cancelled
/// Lines without a recognized prefix become `.pending` with the raw
/// line (trimmed) as content. Blank lines are skipped.
public func parseTodoText(_ text: String) -> [TodoItem] {
    text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { rawLine in
        let line = String(rawLine).trimmingCharacters(in: .whitespaces)
        if line.isEmpty { return nil }

        if let stripped = line.stripping(prefix: "[done]") {
            return TodoItem(content: stripped, status: .completed)
        }
        if let stripped = line.stripping(prefix: "[wip]") {
            return TodoItem(content: stripped, status: .inProgress)
        }
        if let stripped = line.stripping(prefix: "[todo]") {
            return TodoItem(content: stripped, status: .pending)
        }
        if let stripped = line.stripping(prefix: "[cancelled]") {
            return TodoItem(content: stripped, status: .cancelled)
        }
        return TodoItem(content: line, status: .pending)
    }
}

private extension String {
    /// Returns the substring after `prefix`, trimmed of surrounding
    /// whitespace, or nil if `self` does not start with `prefix`.
    func stripping(prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - TodoDockView

/// Sticky bottom dock rendering the latest todo snapshot for the current
/// session. Mounted via `safeAreaInset(.bottom)` on `StreamingDetailView`.
/// Returns an empty view when there are no items so the safe-area inset
/// reserves no space.
public struct TodoDockView: View {
    public let text: String
    @Binding public var isCollapsed: Bool

    public init(text: String, isCollapsed: Binding<Bool>) {
        self.text = text
        self._isCollapsed = isCollapsed
    }

    private var items: [TodoItem] { parseTodoText(text) }
    private var completedCount: Int { items.filter { $0.status == .completed }.count }

    public var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 0) {
                header
                if !isCollapsed {
                    list
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .liquidGlass(in: RoundedRectangle(cornerRadius: 22), interactive: false)
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
            .animation(.easeInOut(duration: 0.2), value: isCollapsed)
        }
    }

    private var header: some View {
        Button {
            isCollapsed.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checklist")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(items.count) tasks · \(completedCount) done")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 180))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 20, alignment: .trailing)
                        Image(systemName: icon(for: item.status))
                            .font(.caption)
                            .foregroundStyle(color(for: item.status))
                            .padding(.top, 3)
                        Text(item.content)
                            .font(.subheadline)
                            .strikethrough(item.status == .completed)
                            .foregroundStyle(item.status == .completed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .frame(maxHeight: 175)
    }

    private func icon(for status: TodoItemStatus) -> String {
        switch status {
        case .completed: "checkmark.circle.fill"
        case .inProgress: "clock"
        case .pending: "circle"
        case .cancelled: "xmark.circle"
        }
    }

    private func color(for status: TodoItemStatus) -> Color {
        switch status {
        case .completed: .green
        case .inProgress: .blue
        case .pending, .cancelled: .secondary
        }
    }
}
