package tech.teamclaw.android.feature.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import tech.teamclaw.android.core.design.Hai
import tech.teamclaw.android.core.design.TeamclawTheme

@Composable
fun CreateTeamScreen(
    isBusy: Boolean,
    errorMessage: String?,
    onCreate: (name: String) -> Unit,
    modifier: Modifier = Modifier,
) {
    var name by remember { mutableStateOf("") }
    Column(
        modifier = modifier.fillMaxSize().background(Hai.Mist).padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(24.dp),
    ) {
        Spacer(Modifier.fillMaxWidth())
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Create Your Team", style = MaterialTheme.typography.headlineMedium, color = Hai.Onyx)
            Text(
                "Name the team you'll be collaborating with. You can invite teammates and agents after this.",
                style = MaterialTheme.typography.bodyLarge, color = Hai.Basalt,
            )
        }
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Team Name", style = MaterialTheme.typography.titleLarge, color = Hai.Onyx)
            OutlinedTextField(
                value = name, onValueChange = { name = it },
                label = { Text("Teamclaw Team") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().testTag("createTeam.nameField"),
                shape = RoundedCornerShape(16.dp),
            )
        }
        if (!errorMessage.isNullOrEmpty()) {
            Text(errorMessage, style = MaterialTheme.typography.bodySmall, color = Hai.CinnabarDeep)
        }
        Button(
            onClick = { onCreate(name) },
            enabled = !isBusy,
            modifier = Modifier.fillMaxWidth().testTag("createTeam.submitButton"),
            shape = RoundedCornerShape(18.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Hai.Cinnabar),
        ) {
            if (isBusy) CircularProgressIndicator(strokeWidth = 2.dp)
            Text("Create Team", style = MaterialTheme.typography.labelLarge, modifier = Modifier.padding(8.dp))
        }
    }
}

@Preview
@Composable
private fun CreateTeamPreview() {
    TeamclawTheme { CreateTeamScreen(false, null, {}) }
}
