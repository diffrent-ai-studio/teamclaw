import SwiftUI
import Foundation
import MarkdownUI

/// Renders CommonMark + GFM markdown (headings, lists, fenced code blocks,
/// tables, inline emphasis/links/code, blockquotes) as SwiftUI views.
///
/// Backed by `swift-markdown-ui` (gonzalezreal). Apple's built-in
/// `AttributedString(markdown:)` only handles inline syntax, so before
/// this swap the chat bubbles dropped raw `##`, table pipes, and bullet
/// dashes into the rendered text whenever the agent replied with
/// anything block-structured.
public struct MarkdownRenderer: View {
    public let content: String

    public init(content: String) {
        self.content = content
    }

    public var body: some View {
        Markdown(content)
            .markdownTheme(Theme.chatBubble)
            .textSelection(.enabled)
    }
}

@MainActor
private extension Theme {
    /// Chat-bubble theme: subheadline-sized body to match the rest of
    /// the bubble's typography, tightened heading scale (we render
    /// inside a narrow column), and a monospaced code font that keeps
    /// inline `code` legible against the gray glass background.
    ///
    /// `@MainActor` because `Theme` is non-Sendable; SwiftUI body
    /// already runs on the main actor so accessing this from a chat
    /// view is free.
    static var chatBubble: Theme {
        Theme()
        // Match the user-bubble's `.subheadline` (15pt) so the two
        // sides of the conversation read at the same visual weight.
        // MarkdownUI's default body is `.body` (17pt) which made
        // user prompts look one notch larger than agent replies.
        .text {
            FontSize(15)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.92))
        }
        .heading1 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.35))
                }
                .padding(.vertical, 4)
        }
        .heading2 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.2))
                }
                .padding(.vertical, 3)
        }
        .heading3 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.08))
                }
                .padding(.vertical, 2)
        }
        .codeBlock { configuration in
            ScrollView(.horizontal) {
                configuration.label
                    .relativeLineSpacing(.em(0.2))
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(.em(0.88))
                    }
                    .padding(10)
            }
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .table { configuration in
            ScrollView(.horizontal) {
                configuration.label
                    .padding(.vertical, 2)
            }
        }
    }
}
