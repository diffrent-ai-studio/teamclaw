package tech.teamclaw.android.core.auth

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.datetime.Instant
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import tech.teamclaw.android.core.model.MessageRecord
import java.util.UUID

interface MessagesRepository {
    suspend fun listMessages(sessionId: String, limit: Int = 200): List<MessageRecord>

    /**
     * Insert a human-authored chat message. Daemon-side agent replies are
     * inserted by the daemon, not the mobile client.
     */
    suspend fun insertUserMessage(
        teamId: String,
        sessionId: String,
        senderActorId: String,
        content: String,
        mentionActorIds: List<String> = emptyList(),
    ): MessageRecord
}

class SupabaseMessagesRepository(
    private val client: SupabaseClient,
) : MessagesRepository {

    override suspend fun listMessages(sessionId: String, limit: Int): List<MessageRecord> {
        val rows: List<MessageRow> = client.postgrest.from("messages")
            .select(
                columns = Columns.list(
                    "id", "session_id", "sender_actor_id", "kind", "content",
                    "created_at", "metadata", "turn_id",
                ),
            ) {
                filter { eq("session_id", sessionId) }
                order("created_at", order = Order.ASCENDING)
                limit(limit.toLong())
            }
            .decodeList()

        return rows.map { it.toRecord() }
    }

    override suspend fun insertUserMessage(
        teamId: String,
        sessionId: String,
        senderActorId: String,
        content: String,
        mentionActorIds: List<String>,
    ): MessageRecord {
        val id = UUID.randomUUID().toString().lowercase()
        val row = MessageInsertRow(
            id = id,
            teamId = teamId,
            sessionId = sessionId,
            senderActorId = senderActorId,
            kind = "text",
            content = content,
            metadata = buildMetadata(mentionActorIds),
        )
        client.postgrest.from("messages").insert(row)

        return MessageRecord(
            id = id,
            sessionId = sessionId,
            senderActorId = senderActorId,
            kind = "text",
            content = content,
            createdAtMs = System.currentTimeMillis(),
            model = null,
            turnId = null,
        )
    }

    private fun buildMetadata(mentionActorIds: List<String>): JsonObject? {
        if (mentionActorIds.isEmpty()) return null
        return kotlinx.serialization.json.buildJsonObject {
            put(
                "mention_actor_ids",
                kotlinx.serialization.json.buildJsonArray {
                    mentionActorIds.forEach { add(kotlinx.serialization.json.JsonPrimitive(it)) }
                },
            )
        }
    }

    private fun MessageRow.toRecord(): MessageRecord {
        val model = metadata?.get("model")?.jsonPrimitive?.content
        return MessageRecord(
            id = id,
            sessionId = sessionId,
            senderActorId = senderActorId,
            kind = kind.orEmpty(),
            content = content.orEmpty(),
            createdAtMs = createdAt.toEpochMilliseconds(),
            model = model,
            turnId = turnId,
        )
    }

    @Serializable
    private data class MessageRow(
        val id: String,
        @SerialName("session_id") val sessionId: String,
        @SerialName("sender_actor_id") val senderActorId: String,
        val kind: String?,
        val content: String?,
        @SerialName("created_at") val createdAt: Instant,
        val metadata: JsonObject? = null,
        @SerialName("turn_id") val turnId: String? = null,
    )

    @Serializable
    private data class MessageInsertRow(
        val id: String,
        @SerialName("team_id") val teamId: String,
        @SerialName("session_id") val sessionId: String,
        @SerialName("sender_actor_id") val senderActorId: String,
        val kind: String,
        val content: String,
        val metadata: JsonObject? = null,
    )
}
