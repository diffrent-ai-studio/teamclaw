package tech.teamclaw.android.feature.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import tech.teamclaw.android.core.design.Hai

/**
 * Render a plain-text message that may contain a subset of CommonMark:
 *   - **bold**, __bold__
 *   - *italic*, _italic_
 *   - `inline code`
 *   - ```fenced code blocks```
 *
 * Full CommonMark (links, lists, tables, blockquotes) intentionally out
 * of scope — port the existing swift-markdown AMUXSharedUI renderer
 * surface to a richer Compose markdown library when we need it.
 *
 * Text color flows through [contentColor]; code block backgrounds use
 * the design's Pebble tone regardless of the caller.
 */
@Composable
fun MarkdownText(
    raw: String,
    contentColor: Color,
    modifier: Modifier = Modifier,
) {
    val blocks = remember(raw) { splitFencedBlocks(raw) }
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        blocks.forEach { block ->
            when (block) {
                is MdBlock.Code -> CodeBlock(text = block.code)
                is MdBlock.Text -> Text(
                    text = renderInline(block.text, contentColor),
                    style = MaterialTheme.typography.bodyLarge,
                    color = contentColor,
                )
            }
        }
    }
}

private sealed interface MdBlock {
    data class Code(val code: String) : MdBlock
    data class Text(val text: String) : MdBlock
}

private val fencePattern = Regex("```(?:[A-Za-z0-9_+\\-]+)?\\n([\\s\\S]*?)```", RegexOption.MULTILINE)

private fun splitFencedBlocks(raw: String): List<MdBlock> {
    val results = mutableListOf<MdBlock>()
    var cursor = 0
    fencePattern.findAll(raw).forEach { match ->
        if (match.range.first > cursor) {
            val text = raw.substring(cursor, match.range.first).trim()
            if (text.isNotEmpty()) results += MdBlock.Text(text)
        }
        results += MdBlock.Code(match.groupValues[1].trimEnd())
        cursor = match.range.last + 1
    }
    if (cursor < raw.length) {
        val tail = raw.substring(cursor).trim()
        if (tail.isNotEmpty()) results += MdBlock.Text(tail)
    }
    if (results.isEmpty()) results += MdBlock.Text(raw)
    return results
}

@Composable
private fun CodeBlock(text: String) {
    val scroll = rememberScrollState()
    androidx.compose.foundation.layout.Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(Hai.Pebble)
            .padding(horizontal = 12.dp, vertical = 8.dp)
            .horizontalScroll(scroll),
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.bodySmall.copy(
                fontFamily = FontFamily.Monospace,
            ),
            color = Hai.Onyx,
            softWrap = false,
            overflow = TextOverflow.Visible,
        )
    }
}

/**
 * Apply bold / italic / inline-code spans onto a single AnnotatedString
 * line. We walk tokens — the lexer is intentionally tiny because chat
 * messages rarely nest these.
 */
private fun renderInline(text: String, baseColor: Color): AnnotatedString = buildAnnotatedString {
    val tokens = tokenizeInline(text)
    for (t in tokens) {
        when (t) {
            is InlineToken.Plain -> append(t.text)
            is InlineToken.Bold -> withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(t.text) }
            is InlineToken.Italic -> withStyle(SpanStyle(fontStyle = FontStyle.Italic)) { append(t.text) }
            is InlineToken.Code -> withStyle(
                SpanStyle(
                    fontFamily = FontFamily.Monospace,
                    background = Hai.Pebble.copy(alpha = 0.6f),
                    color = baseColor,
                )
            ) { append(t.text) }
        }
    }
}

private sealed interface InlineToken {
    data class Plain(val text: String) : InlineToken
    data class Bold(val text: String) : InlineToken
    data class Italic(val text: String) : InlineToken
    data class Code(val text: String) : InlineToken
}

/**
 * Greedy left-to-right tokenizer. Recognizes `**x**`, `__x__`, `*x*`,
 * `_x_`, `` `x` ``. Unmatched delimiters fall through as plain text.
 */
private fun tokenizeInline(text: String): List<InlineToken> {
    val out = mutableListOf<InlineToken>()
    val plain = StringBuilder()
    var i = 0
    while (i < text.length) {
        val rest = text.substring(i)
        val match: Pair<InlineToken, Int>? = when {
            rest.startsWith("**") -> matchDelim(rest, "**")?.let { InlineToken.Bold(it.first) to it.second }
            rest.startsWith("__") -> matchDelim(rest, "__")?.let { InlineToken.Bold(it.first) to it.second }
            rest.startsWith("`") -> matchDelim(rest, "`")?.let { InlineToken.Code(it.first) to it.second }
            rest.startsWith("*") -> matchDelim(rest, "*")?.let { InlineToken.Italic(it.first) to it.second }
            rest.startsWith("_") -> matchDelim(rest, "_")?.let { InlineToken.Italic(it.first) to it.second }
            else -> null
        }
        if (match != null) {
            if (plain.isNotEmpty()) {
                out += InlineToken.Plain(plain.toString()); plain.clear()
            }
            out += match.first
            i += match.second
        } else {
            plain.append(text[i]); i++
        }
    }
    if (plain.isNotEmpty()) out += InlineToken.Plain(plain.toString())
    return out
}

/**
 * Find a balanced delim..delim run starting at index 0 in [s]. Returns the
 * inner text and the total consumed length (delim + inner + delim), or
 * null if no closing delim before end of string / newline.
 */
private fun matchDelim(s: String, delim: String): Pair<String, Int>? {
    val openLen = delim.length
    val close = s.indexOf(delim, startIndex = openLen)
    if (close < 0) return null
    val inner = s.substring(openLen, close)
    // Refuse to match across newlines (keeps the renderer line-bounded).
    if ('\n' in inner) return null
    if (inner.isEmpty()) return null
    return inner to (close + delim.length)
}

private fun AnnotatedString.Builder.withStyle(style: SpanStyle, block: AnnotatedString.Builder.() -> Unit) {
    val start = length
    block()
    addStyle(style, start, length)
}
