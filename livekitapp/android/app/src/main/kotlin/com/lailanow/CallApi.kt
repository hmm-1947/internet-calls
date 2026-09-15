package com.lailanow

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/**
 * Accepts and rejects a call directly from the native layer.
 *
 * Call actions are normally relayed to Dart through the callkit event stream,
 * which only reaches engines that already have a listener attached. On the
 * first call after the process was killed, the listener can act on the lock
 * screen seconds before any Flutter engine has finished booting and
 * subscribing, so the event is dropped. Doing the request here makes it
 * independent of any Flutter engine being alive.
 *
 * For declines that means `/call/{id}/reject` still fires and the caller stops
 * ringing. Rejects that cannot be delivered right away (no network, no token
 * yet) are queued and retried on the next attempt, app start, or token refresh.
 *
 * For accepts it means `/call/{id}/accept` is issued the instant the button is
 * tapped, in parallel with the cold start, instead of after it. The LiveKit
 * credentials that come back are parked in [takeAccepted] for Dart to pick up
 * once the navigator exists, so a slow DNS/TLS round trip to a remote backend
 * no longer has to fit inside the app's boot window.
 *
 * Both endpoints are idempotent, so a duplicate request from the Dart side is
 * harmless.
 */
object CallApi {

    private const val TAG = "CallApi"

    // Shared with AvatarLoader, which already stores the API base URL here.
    private const val PREFS = "livekitapp_call_prefs"
    private const val KEY_BASE_URL = "api_base_url"
    private const val KEY_AUTH_TOKEN = "auth_token"
    private const val KEY_PENDING = "pending_rejects"
    private const val KEY_ACCEPTED = "accepted_call"

    private const val PENDING_TTL_MS = 15 * 60 * 1000L
    private const val MAX_PENDING = 10
    private val RETRY_DELAYS_MS = longArrayOf(0, 2_000, 5_000, 10_000)

    // An accept is only worth replaying while the caller could still be
    // waiting. The incoming-call screen gives up after 45s and the server
    // stops honouring an accept after 60s, so anything older is dead.
    private const val ACCEPTED_TTL_MS = 90 * 1000L
    // A "retryable" failure here almost always means base_url/auth token are
    // not mirrored into native prefs yet, which only happens once the Dart
    // engine has booted far enough to call setApiBaseUrl/setAuthToken. On a
    // fully-killed process (cold start from the notification's Answer
    // action, no existing task), that boot can take well past a few seconds
    // on a throttled/Doze'd device — the old 0/1s/2s/4s schedule (~7s total)
    // routinely lost that race and gave up long before Dart was ready, which
    // silently dropped the accept: postAccept was never retried again, so
    // takeAccepted() had nothing for flushPendingNav() to adopt. Keep trying
    // for close to the full ACCEPTED_TTL_MS window instead.
    private val ACCEPT_RETRY_DELAYS_MS = longArrayOf(
        0, 1_000, 2_000, 3_000, 5_000, 5_000, 8_000, 8_000, 10_000, 10_000, 15_000, 15_000
    )

    private val executor = Executors.newSingleThreadExecutor()

    // Kept off [executor]: a queued reject can sleep for up to ~17s between
    // retries, and an accept must never wait behind that.
    private val acceptExecutor = Executors.newSingleThreadExecutor()

    @Volatile
    private var acceptInFlightCallId: String? = null

    fun setAuthToken(context: Context, token: String?) {
        val app = context.applicationContext
        prefs(app).edit().apply {
            if (token.isNullOrBlank()) remove(KEY_AUTH_TOKEN) else putString(KEY_AUTH_TOKEN, token)
        }.apply()
        if (!token.isNullOrBlank()) flushPending(app)
    }

    /** True once a listener is logged in on this device (mirrored via setAuthToken). */
    fun hasAuthToken(context: Context): Boolean {
        return !prefs(context.applicationContext).getString(KEY_AUTH_TOKEN, null).isNullOrBlank()
    }

    /** Queues the reject and immediately tries to deliver it. */
    fun reject(context: Context, callId: String) {
        if (callId.isBlank()) return
        val app = context.applicationContext
        enqueue(app, callId)
        flushPending(app)
    }

    /**
     * Accepts [callId] straight away and parks the LiveKit credentials for the
     * Dart side to collect via [takeAccepted].
     *
     * Runs while the app is still cold starting, which is the whole point: the
     * request no longer has to win a race against the boot sequence.
     */
    fun accept(
        context: Context,
        callId: String,
        callerName: String,
        callType: String,
        callerPhotoUrl: String
    ) {
        if (callId.isBlank()) return
        val app = context.applicationContext
        if (acceptInFlightCallId == callId) return
        acceptInFlightCallId = callId
        acceptExecutor.execute {
            try {
                for (delay in ACCEPT_RETRY_DELAYS_MS) {
                    if (delay > 0) {
                        try {
                            Thread.sleep(delay)
                        } catch (e: InterruptedException) {
                            Thread.currentThread().interrupt()
                            return@execute
                        }
                    }
                    val (body, retryable) = postAccept(app, callId)
                    if (body != null) {
                        saveAccepted(app, callId, callerName, callType, callerPhotoUrl, body)
                        return@execute
                    }
                    if (!retryable) return@execute
                }
            } finally {
                acceptInFlightCallId = null
            }
        }
    }

    /**
     * True while an accept request is still on the wire. Dart waits on this
     * instead of firing its own duplicate request during the cold start.
     */
    fun isAcceptPending(): Boolean = acceptInFlightCallId != null

    /**
     * Returns the credentials from a native accept exactly once, then forgets
     * them. Anything older than [ACCEPTED_TTL_MS] is dropped so a call that was
     * never picked up cannot resurrect on a later app start.
     */
    fun takeAccepted(context: Context): Map<String, Any?>? {
        val app = context.applicationContext
        val raw = prefs(app).getString(KEY_ACCEPTED, null) ?: return null
        prefs(app).edit().remove(KEY_ACCEPTED).apply()
        return try {
            val json = JSONObject(raw)
            if (System.currentTimeMillis() - json.optLong("ts") > ACCEPTED_TTL_MS) {
                Log.d(TAG, "accepted call ${json.optString("call_id")} dropped: too old to replay")
                return null
            }
            mapOf(
                "call_id" to json.optString("call_id"),
                "token" to json.optString("token"),
                "livekit_url" to json.optString("livekit_url"),
                "room_name" to json.optString("room_name"),
                "call_type" to json.optString("call_type"),
                "caller_name" to json.optString("caller_name"),
                "caller_photo_url" to json.optString("caller_photo_url")
            )
        } catch (e: Exception) {
            Log.d(TAG, "takeAccepted threw: $e")
            null
        }
    }

    /** @return the response body on success, and whether a retry is worthwhile. */
    private fun postAccept(context: Context, callId: String): Pair<String?, Boolean> {
        val base = prefs(context).getString(KEY_BASE_URL, "").orEmpty()
        val token = prefs(context).getString(KEY_AUTH_TOKEN, "").orEmpty()
        if (base.isEmpty() || token.isEmpty()) {
            Log.d(TAG, "accept $callId deferred: base url or token not available yet")
            return null to true
        }
        var connection: HttpURLConnection? = null
        return try {
            connection = (URL("$base/call/$callId/accept").openConnection() as HttpURLConnection)
                .apply {
                    connectTimeout = 15_000
                    readTimeout = 15_000
                    requestMethod = "POST"
                    doOutput = true
                    setRequestProperty("Content-Type", "application/json")
                    setRequestProperty("Authorization", "Bearer $token")
                }
            connection.outputStream.use { it.write("{}".toByteArray()) }
            val code = connection.responseCode
            Log.d(TAG, "accept $callId -> HTTP $code")
            if (code == 200) {
                connection.inputStream.bufferedReader().use { it.readText() } to false
            } else {
                // 401 is worth another try once a fresh token has been pushed
                // down; 5xx once the server recovers. A 4xx refusal (cancelled,
                // timed out, already ended) is final.
                null to (code == 401 || code >= 500)
            }
        } catch (e: Exception) {
            // DNS, TLS or read timeout on a radio that just woke from Doze:
            // exactly the case this retry loop exists for.
            Log.d(TAG, "accept $callId threw: $e")
            null to true
        } finally {
            try {
                connection?.disconnect()
            } catch (_: Exception) {
            }
        }
    }

    private fun saveAccepted(
        context: Context,
        callId: String,
        callerName: String,
        callType: String,
        callerPhotoUrl: String,
        body: String
    ) {
        try {
            val response = JSONObject(body)
            val stored = JSONObject()
                .put("call_id", callId)
                .put("ts", System.currentTimeMillis())
                .put("token", response.optString("token"))
                .put("livekit_url", response.optString("livekit_url"))
                .put("room_name", response.optString("room_name"))
                // The server knows the authoritative call type; the intent
                // extra is only the fallback when it is missing.
                .put("call_type", response.optString("call_type").ifEmpty { callType })
                .put("caller_name", callerName)
                .put("caller_photo_url", callerPhotoUrl)
            prefs(context).edit().putString(KEY_ACCEPTED, stored.toString()).apply()
            Log.d(TAG, "accept $callId stored for pickup by Dart")
        } catch (e: Exception) {
            Log.d(TAG, "saveAccepted threw: $e")
        }
    }

    fun flushPending(context: Context) {
        val app = context.applicationContext
        executor.execute {
            for (delay in RETRY_DELAYS_MS) {
                val pending = pending(app)
                if (pending.isEmpty()) return@execute
                if (delay > 0) {
                    try {
                        Thread.sleep(delay)
                    } catch (e: InterruptedException) {
                        Thread.currentThread().interrupt()
                        return@execute
                    }
                }
                var retryNeeded = false
                for (callId in pending) {
                    if (postReject(app, callId)) dequeue(app, callId) else retryNeeded = true
                }
                if (!retryNeeded) return@execute
            }
        }
    }

    /** @return true when the reject is settled and must not be retried. */
    private fun postReject(context: Context, callId: String): Boolean {
        val base = prefs(context).getString(KEY_BASE_URL, "").orEmpty()
        val token = prefs(context).getString(KEY_AUTH_TOKEN, "").orEmpty()
        if (base.isEmpty() || token.isEmpty()) {
            Log.d(TAG, "reject $callId deferred: base url or token not available yet")
            return false
        }
        var connection: HttpURLConnection? = null
        return try {
            connection = (URL("$base/call/$callId/reject").openConnection() as HttpURLConnection)
                .apply {
                    connectTimeout = 10_000
                    readTimeout = 10_000
                    requestMethod = "POST"
                    doOutput = true
                    setRequestProperty("Content-Type", "application/json")
                    setRequestProperty("Authorization", "Bearer $token")
                }
            connection.outputStream.use { it.write("{}".toByteArray()) }
            val code = connection.responseCode
            Log.d(TAG, "reject $callId -> HTTP $code")
            // 401 is worth another try once a fresh token has been pushed down;
            // 5xx is worth another try once the server recovers. Anything else
            // (including "already rejected") is final.
            code != 401 && code < 500
        } catch (e: Exception) {
            Log.d(TAG, "reject $callId threw: $e")
            false
        } finally {
            try {
                connection?.disconnect()
            } catch (_: Exception) {
            }
        }
    }

    private fun enqueue(context: Context, callId: String) {
        val entries = entries(context)
        if (entries.any { it.first == callId }) return
        entries.add(callId to System.currentTimeMillis())
        while (entries.size > MAX_PENDING) entries.removeAt(0)
        save(context, entries)
    }

    private fun dequeue(context: Context, callId: String) {
        val entries = entries(context)
        if (entries.removeAll { it.first == callId }) save(context, entries)
    }

    private fun pending(context: Context): List<String> = entries(context).map { it.first }

    /** Reads the queue, dropping entries too old to still matter. */
    private fun entries(context: Context): MutableList<Pair<String, Long>> {
        val out = mutableListOf<Pair<String, Long>>()
        val now = System.currentTimeMillis()
        try {
            val array = JSONArray(prefs(context).getString(KEY_PENDING, "[]"))
            for (i in 0 until array.length()) {
                val item = array.optJSONObject(i) ?: continue
                val id = item.optString("id")
                val ts = item.optLong("ts")
                if (id.isEmpty() || now - ts > PENDING_TTL_MS) continue
                out.add(id to ts)
            }
        } catch (e: Exception) {
            Log.d(TAG, "entries threw: $e")
        }
        return out
    }

    private fun save(context: Context, entries: List<Pair<String, Long>>) {
        val array = JSONArray()
        entries.forEach { (id, ts) ->
            array.put(JSONObject().put("id", id).put("ts", ts))
        }
        prefs(context).edit().putString(KEY_PENDING, array.toString()).apply()
    }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
