import SwiftUI

public struct BlockMarkdownView: View {
    let blocks: [MarkdownBlock]
    let baseFont: Font
    let codeFont: Font

    public init(
        source: String,
        baseFont: Font = .system(size: 14),
        codeFont: Font = .system(size: 12, design: .monospaced)
    ) {
        self.blocks = MarkdownBlock.parse(source)
        self.baseFont = baseFont
        self.codeFont = codeFont
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            Text(inlineMarkdown(text))
                .font(baseFont)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

        case .heading(let level, let text):
            Text(text)
                .font(.system(size: max(13, 22 - CGFloat(level - 1) * 2), weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)

        case .codeBlock(_, let code):
            Text(code)
                .font(codeFont)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Hai's Pebble token inlined — AMUXCore can't import the
                // higher-level AMUXSharedUI theme module without a cycle.
                .background(
                    Color(red: 0xE2 / 255, green: 0xDF / 255, blue: 0xD9 / 255),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .textSelection(.enabled)

        case .blockQuote(let text):
            Text(inlineMarkdown(text))
                .font(baseFont)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 3)
                }

        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text(ordered ? "\(idx + 1)." : "•")
                            .font(baseFont)
                            .foregroundStyle(.secondary)
                            .frame(width: 18, alignment: .trailing)
                        Text(inlineMarkdown(item))
                            .font(baseFont)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
