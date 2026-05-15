package tech.teamclaw.android.feature.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import tech.teamclaw.android.core.design.Hai
import tech.teamclaw.android.core.design.TeamclawTheme

@Composable
fun LoginScreen(
    pendingEmail: String?,
    isBusy: Boolean,
    errorMessage: String?,
    onSendCode: (email: String) -> Unit,
    onVerifyCode: (email: String, code: String) -> Unit,
    onUseDifferentEmail: () -> Unit,
    onSignInWithApple: () -> Unit,
    onSignInWithGoogle: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.fillMaxSize().background(Hai.Mist)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 24.dp)
            .padding(top = 72.dp, bottom = 36.dp),
        verticalArrangement = Arrangement.spacedBy(24.dp),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(
                if (pendingEmail != null) "Enter the code" else "Sign in",
                style = MaterialTheme.typography.headlineLarge, color = Hai.Onyx,
            )
            Text(
                if (pendingEmail != null) "Check your inbox for an 8-digit code."
                else "We'll email you an 8-digit code.",
                style = MaterialTheme.typography.bodyLarge, color = Hai.Basalt,
            )
        }

        if (pendingEmail != null) {
            CodeEntrySection(
                pendingEmail = pendingEmail,
                isBusy = isBusy,
                onVerify = { code -> onVerifyCode(pendingEmail, code) },
                onUseDifferentEmail = onUseDifferentEmail,
            )
        } else {
            EmailEntrySection(isBusy = isBusy, onSubmit = onSendCode)
        }

        if (!errorMessage.isNullOrEmpty()) {
            Text(errorMessage, style = MaterialTheme.typography.bodySmall, color = Hai.CinnabarDeep)
        }

        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            HorizontalDivider(Modifier.weight(1f), thickness = 0.5.dp, color = Hai.Hairline)
            Text("or", style = MaterialTheme.typography.bodySmall, color = Hai.Slate)
            HorizontalDivider(Modifier.weight(1f), thickness = 0.5.dp, color = Hai.Hairline)
        }

        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            SocialButton("Sign in with Apple", isBusy, onSignInWithApple)
            SocialButton("Sign in with Google", isBusy, onSignInWithGoogle)
        }
    }
}

@Composable
private fun EmailEntrySection(isBusy: Boolean, onSubmit: (String) -> Unit) {
    var email by remember { mutableStateOf("") }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        OutlinedTextField(
            value = email, onValueChange = { email = it },
            label = { Text("Email") },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
            singleLine = true,
            modifier = Modifier.fillMaxWidth().testTag("login.emailField"),
            shape = RoundedCornerShape(16.dp),
        )
        PrimaryButton("Send code", isBusy = isBusy, enabled = email.isNotBlank()) {
            onSubmit(email)
        }
    }
}

@Composable
private fun CodeEntrySection(
    pendingEmail: String,
    isBusy: Boolean,
    onVerify: (code: String) -> Unit,
    onUseDifferentEmail: () -> Unit,
) {
    var code by remember { mutableStateOf("") }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Code sent to $pendingEmail", style = MaterialTheme.typography.bodySmall, color = Hai.Basalt)
        OutlinedTextField(
            value = code,
            onValueChange = { code = it.filter(Char::isDigit).take(8) },
            label = { Text("8-digit code") },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
            singleLine = true,
            modifier = Modifier.fillMaxWidth().testTag("login.codeField"),
            shape = RoundedCornerShape(16.dp),
        )
        PrimaryButton("Verify", isBusy = isBusy, enabled = code.length == 8) {
            onVerify(code)
        }
        TextButton(
            onClick = onUseDifferentEmail,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text("Use a different email", color = Hai.CinnabarDeep)
        }
    }
}

@Composable
private fun PrimaryButton(label: String, isBusy: Boolean, enabled: Boolean, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        enabled = enabled && !isBusy,
        modifier = Modifier.fillMaxWidth().testTag("login.submitButton"),
        shape = RoundedCornerShape(18.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = Hai.Cinnabar,
            disabledContainerColor = Hai.Pebble.copy(alpha = 0.82f),
        ),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (isBusy) CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
            Text(label, style = MaterialTheme.typography.labelLarge)
        }
    }
}

@Composable
private fun SocialButton(label: String, isBusy: Boolean, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        enabled = !isBusy,
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(18.dp),
        colors = ButtonDefaults.buttonColors(containerColor = Hai.Paper.copy(alpha = 0.82f)),
    ) {
        Text(label, style = MaterialTheme.typography.labelLarge, color = Hai.Onyx)
    }
}

@Preview
@Composable
private fun LoginEmailPreview() {
    TeamclawTheme {
        LoginScreen(null, false, null, {}, { _, _ -> }, {}, {}, {})
    }
}
