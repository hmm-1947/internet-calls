package com.lailanow

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/**
 * Rejects a call directly from the native layer.
 *
 * Declines are normally relayed to Dart through the callkit event stream, which
 * only reaches engines that already have a listener attached. On the first call
 * after the process was killed, the listener can decline from the lock screen
 * seconds before the FCM background isolate has finished booting and
 * subscribing, so the event is dropped, `/call/{id}/reject` is never called and
 * the caller keeps ringing. Doing the reject here makes it independent of any
 * Flutter engine being alive.
 *
 * Rejects that cannot be delivered right away (no network, no token yet) are
 * queued and retried on the next attempt, app start, or token refresh. The
 * endpoint is idempotent, so a duplicate reject from the Dart side is a no-op.
 */
object CallApi {

    private const val TAG = "CallApi"

    // Shared with AvatarLoader, which already stores the API base URL here.
    private const val PREFS = "livekitapp_call_prefs"
    private const val KEY_BASE_URL = "api_base_url"
    private const val KEY_AUTH_TOKEN = "auth_token"
    private const val KEY_PENDING = "pending_rejects"

    private const val PENDING_TTL_MS = 15 * 60 * 1000L
    private const val MAX_PENDING = 10
    private val RETRY_DELAYS_MS = longArrayOf(0, 2_000, 5_000, 10_000)

    private val executor = Executors.newSingleThreadExecutor()

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
