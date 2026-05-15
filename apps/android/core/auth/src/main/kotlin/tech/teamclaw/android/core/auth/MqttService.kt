package tech.teamclaw.android.core.auth

import com.hivemq.client.mqtt.MqttClient
import com.hivemq.client.mqtt.datatypes.MqttQos
import com.hivemq.client.mqtt.mqtt3.Mqtt3AsyncClient
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.callbackFlow
import java.util.UUID

/**
 * Minimal MQTT realtime layer. Mirrors the iOS MQTTService's role of
 * "tell me when something happened on this topic" — the payload is not
 * decoded here; consumers re-fetch from PostgREST on each signal. Full
 * proto decoding (Amux_RuntimeInfo, tool events, etc.) deferred to a
 * later phase.
 *
 * Connect once per signed-in session (JWT is the password). The broker
 * accepts the JWT for ~1h; reconnect on token refresh.
 */
class MqttService(
    private val host: String,
    private val port: Int,
    private val useTls: Boolean,
) {
    data class TopicEvent(val topic: String, val payload: ByteArray)

    private var client: Mqtt3AsyncClient? = null
    private val events = MutableSharedFlow<TopicEvent>(extraBufferCapacity = 64)

    /**
     * Single flow of all received messages across all subscribed topics.
     * Consumers filter by topic.
     */
    val incoming: Flow<TopicEvent> = events.asSharedFlow()

    /**
     * Connect to the broker. Idempotent: calling twice with the same
     * credentials is a no-op.
     */
    suspend fun connect(userId: String, accessToken: String) {
        if (client != null) return
        val builder = MqttClient.builder()
            .useMqttVersion3()
            .identifier("teamclaw-android-${UUID.randomUUID().toString().substring(0, 8)}")
            .serverHost(host)
            .serverPort(port)
            .also { if (useTls) it.sslWithDefaultConfig() }
        val c = builder.buildAsync()

        c.connectWith()
            .simpleAuth()
            .username(userId)
            .password(accessToken.toByteArray(Charsets.UTF_8))
            .applySimpleAuth()
            .send()
            .await()
        client = c
    }

    suspend fun disconnect() {
        client?.disconnect()?.await()
        client = null
    }

    /**
     * Subscribe to a topic filter (supports `+` wildcards). Returns a flow
     * that emits a Unit each time the broker delivers a message matching
     * the filter. The actual MQTT subscription stays alive until the
     * collector cancels.
     */
    fun subscribeAsSignal(topicFilter: String): Flow<Unit> = callbackFlow {
        val c = client
        if (c == null) {
            close()
            return@callbackFlow
        }
        c.subscribeWith()
            .topicFilter(topicFilter)
            .qos(MqttQos.AT_LEAST_ONCE)
            .callback { msg ->
                events.tryEmit(TopicEvent(msg.topic.toString(), msg.payloadAsBytes ?: ByteArray(0)))
                trySend(Unit)
            }
            .send()
            .await()
        awaitClose {
            // Best-effort unsubscribe; if the client is already gone, this
            // is a no-op.
            client?.unsubscribeWith()?.topicFilter(topicFilter)?.send()
        }
    }
}

private suspend fun <T> java.util.concurrent.CompletableFuture<T>.await(): T =
    kotlinx.coroutines.suspendCancellableCoroutine { cont ->
        whenComplete { value, error ->
            if (error != null) cont.resumeWith(Result.failure(error))
            else cont.resumeWith(Result.success(value))
        }
        cont.invokeOnCancellation { cancel(true) }
    }
