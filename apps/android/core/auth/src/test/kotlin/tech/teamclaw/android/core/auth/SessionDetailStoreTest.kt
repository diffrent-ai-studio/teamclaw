package tech.teamclaw.android.core.auth

import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test
import tech.teamclaw.android.core.model.MessageRecord

@OptIn(ExperimentalCoroutinesApi::class)
class SessionDetailStoreTest {

    private class FakeMessagesRepo(
        var rows: List<MessageRecord> = emptyList(),
        var listError: Throwable? = null,
        var sendError: Throwable? = null,
    ) : MessagesRepository {
        val inserted = mutableListOf<String>()

        override suspend fun listMessages(sessionId: String, limit: Int): List<MessageRecord> {
            listError?.let { throw it }
            return rows
        }

        override suspend fun insertUserMessage(
            teamId: String, sessionId: String, senderActorId: String,
            content: String, mentionActorIds: List<String>,
        ): MessageRecord {
            sendError?.let { throw it }
            inserted += content
            return MessageRecord(
                id = "inserted-${inserted.size}",
                sessionId = sessionId,
                senderActorId = senderActorId,
                kind = "text", content = content,
                createdAtMs = 0L, model = null, turnId = null,
            )
        }
    }

    private fun sampleMessage(id: String, sender: String, content: String) = MessageRecord(
        id = id, sessionId = "S", senderActorId = sender,
        kind = "text", content = content,
        createdAtMs = 0L, model = null, turnId = null,
    )

    @Test fun `reload populates messages`() = runTest {
        val repo = FakeMessagesRepo(rows = listOf(sampleMessage("1", "me", "hi")))
        val store = SessionDetailStore("T", "S", "me", repo)

        store.reload()

        assertThat(store.state.value.messages).hasSize(1)
        assertThat(store.state.value.errorMessage).isNull()
    }

    @Test fun `send appends inserted message to state`() = runTest {
        val repo = FakeMessagesRepo()
        val store = SessionDetailStore("T", "S", "me", repo)

        store.send("hello")

        assertThat(repo.inserted).containsExactly("hello")
        assertThat(store.state.value.messages.map { it.content }).containsExactly("hello")
        assertThat(store.state.value.isSending).isFalse()
    }

    @Test fun `send rejects blank content`() = runTest {
        val repo = FakeMessagesRepo()
        val store = SessionDetailStore("T", "S", "me", repo)

        store.send("   ")

        assertThat(repo.inserted).isEmpty()
        assertThat(store.state.value.messages).isEmpty()
    }

    @Test fun `send surfaces error and clears sending flag`() = runTest {
        val repo = FakeMessagesRepo(sendError = RuntimeException("rls denied"))
        val store = SessionDetailStore("T", "S", "me", repo)

        store.send("hello")

        assertThat(store.state.value.errorMessage).contains("rls denied")
        assertThat(store.state.value.isSending).isFalse()
    }
}
