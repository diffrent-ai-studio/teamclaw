package tech.teamclaw.android.feature.onboarding.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.dp
import tech.teamclaw.android.core.design.Hai

private data class Card(val title: String, val accent: Color, val offsetX: Int, val offsetY: Int)

@Composable
fun RoleCardsIllustration(modifier: Modifier = Modifier) {
    val cards = listOf(
        Card("Sales",   Hai.Cinnabar, -40, -18),
        Card("Support", Hai.Sage,      42,   2),
        Card("Ops",     Hai.Basalt,    -8,  42),
    )
    Box(modifier = modifier.width(236.dp).height(144.dp)) {
        ConnectionLine(Modifier.width(236.dp).height(144.dp))
        cards.forEach { card -> RoleCardView(card, Modifier.offset(card.offsetX.dp, card.offsetY.dp)) }
        Box(
            modifier = Modifier.offset(72.dp, (-36).dp).size(8.dp)
                .background(Hai.Cinnabar, CircleShape),
        )
    }
}

@Composable
private fun ConnectionLine(modifier: Modifier) {
    Canvas(modifier) {
        val path1 = Path().apply {
            moveTo(50f, 42f)
            cubicTo(82f, 18f, 136f, 18f, 172f, 38f)
        }
        val path2 = Path().apply {
            moveTo(70f, 84f)
            cubicTo(96f, 98f, 134f, 96f, 168f, 74f)
        }
        val effect = PathEffect.dashPathEffect(floatArrayOf(4f, 6f), 0f)
        drawPath(path1, Hai.Hairline, style = Stroke(width = 1f, pathEffect = effect))
        drawPath(path2, Hai.Hairline, style = Stroke(width = 1f, pathEffect = effect))
    }
}

@Composable
private fun RoleCardView(card: Card, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .width(104.dp).height(70.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(Hai.Paper)
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(9.dp),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(7.dp),
        ) {
            Box(Modifier.size(9.dp).clip(CircleShape).background(card.accent))
            Text(card.title, style = MaterialTheme.typography.bodySmall, color = Hai.Onyx)
            Spacer(Modifier.weight(1f))
        }
        Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Box(Modifier.width(62.dp).height(5.dp).clip(RoundedCornerShape(50)).background(Hai.Basalt.copy(alpha = 0.32f)))
            Box(Modifier.width(42.dp).height(5.dp).clip(RoundedCornerShape(50)).background(Hai.Slate.copy(alpha = 0.28f)))
        }
    }
}
