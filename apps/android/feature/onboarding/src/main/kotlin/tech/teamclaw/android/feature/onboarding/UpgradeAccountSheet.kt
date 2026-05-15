package tech.teamclaw.android.feature.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import tech.teamclaw.android.core.design.Hai

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun UpgradeAccountSheet(
    isBusy: Boolean,
    errorMessage: String?,
    onDismiss: () -> Unit,
    onSubmit: (email: String, password: String) -> Unit,
) {
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    val canSubmit = email.isNotBlank() && password.length >= 8 && !isBusy

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = state) {
        Column(
            modifier = Modifier.padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("Upgrade to a permanent account", style = MaterialTheme.typography.titleLarge)
                Text(
                    "Attach an email + password so this workspace is reachable from any device. Your existing team and history stay with the same user.",
                    style = MaterialTheme.typography.bodyMedium, color = Hai.Basalt,
                )
            }

            OutlinedTextField(
                value = email, onValueChange = { email = it },
                label = { Text("Email") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(12.dp),
            )
            OutlinedTextField(
                value = password, onValueChange = { password = it },
                label = { Text("Password (≥ 8 chars)") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                visualTransformation = PasswordVisualTransformation(),
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(12.dp),
            )

            if (!errorMessage.isNullOrEmpty()) {
                Box(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp))
                        .background(Hai.Cinnabar.copy(alpha = 0.10f)).padding(10.dp),
                ) {
                    Text(errorMessage, style = MaterialTheme.typography.bodySmall, color = Hai.Onyx)
                }
            }

            Button(
                onClick = { onSubmit(email, password) },
                enabled = canSubmit,
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(18.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Hai.Cinnabar),
            ) {
                Text(if (isBusy) "Linking…" else "Link account")
            }
        }
    }
}
