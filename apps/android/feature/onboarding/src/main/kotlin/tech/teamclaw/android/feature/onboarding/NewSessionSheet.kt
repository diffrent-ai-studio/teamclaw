package tech.teamclaw.android.feature.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import tech.teamclaw.android.core.design.Hai
import tech.teamclaw.android.core.model.ActorRecord

data class NewSessionInput(
    val title: String,
    val agentActorId: String,
    val firstMessage: String,
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NewSessionSheet(
    agents: List<ActorRecord>,
    isCreating: Boolean,
    errorMessage: String?,
    onDismiss: () -> Unit,
    onSubmit: (NewSessionInput) -> Unit,
) {
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var title by remember { mutableStateOf("") }
    var firstMessage by remember { mutableStateOf("") }
    var selectedAgent by remember { mutableStateOf(agents.firstOrNull()) }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = state) {
        Column(
            modifier = Modifier.padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text("New session", style = MaterialTheme.typography.titleLarge)

            OutlinedTextField(
                value = title, onValueChange = { title = it },
                label = { Text("Title") },
                modifier = Modifier.fillMaxWidth().testTag("newSession.titleField"),
                shape = RoundedCornerShape(12.dp), singleLine = true,
            )

            Text("Agent", style = MaterialTheme.typography.bodySmall, color = Hai.Slate)
            if (agents.isEmpty()) {
                Box(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp))
                        .background(Hai.Pebble).padding(12.dp),
                ) {
                    Text(
                        "No agents in this team yet. Invite an agent first.",
                        style = MaterialTheme.typography.bodySmall, color = Hai.Basalt,
                    )
                }
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    items(items = agents, key = { it.id }) { agent ->
                        AgentPickerRow(
                            agent = agent,
                            isSelected = selectedAgent?.id == agent.id,
                            onSelect = { selectedAgent = agent },
                        )
                    }
                }
            }

            OutlinedTextField(
                value = firstMessage, onValueChange = { firstMessage = it },
                label = { Text("First message") },
                modifier = Modifier.fillMaxWidth().testTag("newSession.firstMessageField"),
                shape = RoundedCornerShape(12.dp),
                maxLines = 5,
            )

            if (!errorMessage.isNullOrEmpty()) {
                Box(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp))
                        .background(Hai.Cinnabar.copy(alpha = 0.10f)).padding(10.dp),
                ) {
                    Text(errorMessage, style = MaterialTheme.typography.bodySmall, color = Hai.Onyx)
                }
            }

            val canSubmit = !isCreating && title.isNotBlank() &&
                firstMessage.isNotBlank() && selectedAgent != null

            Button(
                onClick = {
                    val agent = selectedAgent ?: return@Button
                    onSubmit(NewSessionInput(title.trim(), agent.id, firstMessage.trim()))
                },
                enabled = canSubmit,
                modifier = Modifier.fillMaxWidth().testTag("newSession.submitButton"),
                shape = RoundedCornerShape(18.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Hai.Cinnabar),
            ) {
                Text(if (isCreating) "Creating…" else "Start session")
            }
        }
    }
}

@Composable
private fun AgentPickerRow(
    agent: ActorRecord,
    isSelected: Boolean,
    onSelect: () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(if (isSelected) Hai.Cinnabar.copy(alpha = 0.12f) else Hai.Paper)
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(
            Modifier.size(32.dp).clip(CircleShape)
                .background(if (agent.isAgent) Hai.Sage else Hai.Cinnabar.copy(alpha = 0.2f)),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                agent.displayName.firstOrNull()?.uppercaseChar()?.toString() ?: "?",
                style = MaterialTheme.typography.labelLarge,
                color = if (agent.isAgent) androidx.compose.ui.graphics.Color.White else Hai.Cinnabar,
            )
        }
        Column(modifier = Modifier.weight(1f)) {
            Text(agent.displayName, style = MaterialTheme.typography.labelLarge, color = Hai.Onyx)
            Text(
                text = if (agent.isAgent) "Agent · ${agent.agentKind ?: "—"}" else agent.roleLabel,
                style = MaterialTheme.typography.bodySmall, color = Hai.Basalt,
            )
        }
        Button(
            onClick = onSelect,
            enabled = !isSelected,
            shape = RoundedCornerShape(14.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = if (isSelected) Hai.Cinnabar else Hai.Paper,
                disabledContainerColor = Hai.Cinnabar,
            ),
        ) {
            Text(if (isSelected) "Selected" else "Pick", color = if (isSelected) androidx.compose.ui.graphics.Color.White else Hai.Cinnabar)
        }
    }
}
