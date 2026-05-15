package tech.teamclaw.android.feature.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import tech.teamclaw.android.core.design.Hai
import tech.teamclaw.android.core.design.TeamclawTheme

@Composable
fun LobsterSplashScreen(modifier: Modifier = Modifier) {
    Box(
        modifier = modifier.fillMaxSize().background(Hai.Mist),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            Text("Teamclaw", style = MaterialTheme.typography.displayLarge, color = Hai.Onyx)
            CircularProgressIndicator(color = Hai.Cinnabar)
        }
    }
}

@Preview
@Composable
private fun LobsterSplashPreview() {
    TeamclawTheme { LobsterSplashScreen() }
}
