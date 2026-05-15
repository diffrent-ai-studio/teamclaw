package tech.teamclaw.android.core.deeplink

import android.net.Uri
import com.google.common.truth.Truth.assertThat
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class DeepLinkParserTest {
    private val parser = DeepLinkParser()

    @Test fun `parses invite token from teamclaw scheme`() {
        val uri = Uri.parse("teamclaw://invite?token=ABC123")
        assertThat(parser.parse(uri)).isEqualTo(DeepLink.InviteToken("ABC123"))
    }

    @Test fun `parses invite token from amux scheme`() {
        val uri = Uri.parse("amux://invite?token=XYZ")
        assertThat(parser.parse(uri)).isEqualTo(DeepLink.InviteToken("XYZ"))
    }

    @Test fun `parses auth callback`() {
        val uri = Uri.parse("teamclaw://auth-callback#access_token=foo&refresh_token=bar")
        val parsed = parser.parse(uri)
        assertThat(parsed).isInstanceOf(DeepLink.AuthCallback::class.java)
        assertThat((parsed as DeepLink.AuthCallback).uri.toString()).isEqualTo(uri.toString())
    }

    @Test fun `unknown host returns null`() {
        val uri = Uri.parse("teamclaw://unknown")
        assertThat(parser.parse(uri)).isNull()
    }

    @Test fun `parseToken accepts bare token`() {
        assertThat(parser.parseToken("ABC123")).isEqualTo("ABC123")
    }

    @Test fun `parseToken accepts URL with token`() {
        assertThat(parser.parseToken("teamclaw://invite?token=XYZ")).isEqualTo("XYZ")
    }

    @Test fun `parseToken rejects URL without token`() {
        assertThat(parser.parseToken("teamclaw://invite")).isNull()
    }

    @Test fun `parseToken trims whitespace`() {
        assertThat(parser.parseToken("  ABC123  \n")).isEqualTo("ABC123")
    }

    @Test fun `parseToken rejects empty`() {
        assertThat(parser.parseToken("")).isNull()
        assertThat(parser.parseToken("   ")).isNull()
    }

    @Test fun `parseToken rejects URL with wrong scheme`() {
        assertThat(parser.parseToken("https://example.com/foo?token=xyz")).isNull()
    }
}
