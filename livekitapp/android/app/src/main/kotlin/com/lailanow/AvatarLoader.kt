package com.lailanow

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Rect
import android.graphics.RectF
import android.os.Handler
import android.os.Looper
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

object AvatarLoader {

    private const val TAG = "AvatarLoader"
    private const val PREFS = "livekitapp_call_prefs"
    private const val KEY_BASE_URL = "api_base_url"
    private const val TARGET_SIZE = 512
    private const val CACHE_DIR = "call_avatars"

    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val memory = ConcurrentHashMap<String, Bitmap>()

    fun setBaseUrl(context: Context, baseUrl: String) {
        if (baseUrl.isBlank()) return
        context.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_BASE_URL, baseUrl.trim().trimEnd('/'))
            .apply()
    }

    fun resolveUrl(context: Context, raw: String?): String {
        val value = raw?.trim().orEmpty()
        if (value.isEmpty()) return ""
        if (value.startsWith("http://", true) || value.startsWith("https://", true)) return value
        if (value.startsWith("file://") || value.startsWith("/data/") ||
            value.startsWith("/storage/")
        ) {
            return value
        }
        val base = context.applicationContext
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_BASE_URL, "")
            .orEmpty()
        if (base.isEmpty()) return ""
        return if (value.startsWith("/")) "$base$value" else "$base/$value"
    }

    fun cached(context: Context, url: String): Bitmap? {
        if (url.isEmpty()) return null
        memory[url]?.let { return it }
        val local = localFile(url)
        if (local != null) {
            return decodeFile(local)?.also { memory[url] = it }
        }
        val file = cacheFileFor(context, url)
        if (!file.exists() || file.length() == 0L) return null
        return decodeFile(file)?.also { memory[url] = it }
    }

    fun load(context: Context, url: String, onLoaded: (Bitmap) -> Unit) {
        if (url.isEmpty()) return
        val appContext = context.applicationContext
        cached(appContext, url)?.let {
            onLoaded(it)
            return
        }
        executor.execute {
            val bitmap = download(appContext, url) ?: return@execute
            memory[url] = bitmap
            main.post { onLoaded(bitmap) }
        }
    }

    private fun localFile(url: String): File? {
        val path = when {
            url.startsWith("file://") -> url.removePrefix("file://")
            url.startsWith("/") -> url
            else -> return null
        }
        val file = File(path)
        return if (file.exists() && file.length() > 0L) file else null
    }

    private fun cacheFileFor(context: Context, url: String): File {
        val dir = File(context.cacheDir, CACHE_DIR)
        if (!dir.exists()) dir.mkdirs()
        return File(dir, "avatar_${url.hashCode()}.png")
    }

    private fun download(context: Context, url: String): Bitmap? {
        localFile(url)?.let { return decodeFile(it) }
        var connection: HttpURLConnection? = null
        return try {
            connection = (URL(url).openConnection() as HttpURLConnection).apply {
                connectTimeout = 8000
                readTimeout = 8000
                instanceFollowRedirects = true
                requestMethod = "GET"
            }
            if (connection.responseCode !in 200..299) return null
            val raw = connection.inputStream.use { it.readBytes() }
            if (raw.isEmpty()) return null
            val decoded = decodeBytes(raw) ?: return null
            val circle = circleCrop(decoded)
            persist(context, url, circle)
            circle
        } catch (e: Exception) {
            android.util.Log.d(TAG, "download threw: $e")
            null
        } finally {
            try {
                connection?.disconnect()
            } catch (_: Exception) {
            }
        }
    }

    private fun persist(context: Context, url: String, bitmap: Bitmap) {
        try {
            cacheFileFor(context, url).outputStream().use {
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
            }
        } catch (e: Exception) {
            android.util.Log.d(TAG, "persist threw: $e")
        }
    }

    private fun decodeFile(file: File): Bitmap? = try {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.absolutePath, bounds)
        val options = BitmapFactory.Options().apply {
            inSampleSize = sampleSize(bounds.outWidth, bounds.outHeight)
        }
        BitmapFactory.decodeFile(file.absolutePath, options)?.let { circleCrop(it) }
    } catch (e: Exception) {
        android.util.Log.d(TAG, "decodeFile threw: $e")
        null
    }

    private fun decodeBytes(bytes: ByteArray): Bitmap? = try {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        val options = BitmapFactory.Options().apply {
            inSampleSize = sampleSize(bounds.outWidth, bounds.outHeight)
        }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
    } catch (e: Exception) {
        android.util.Log.d(TAG, "decodeBytes threw: $e")
        null
    }

    private fun sampleSize(width: Int, height: Int): Int {
        var sample = 1
        var longest = maxOf(width, height)
        while (longest / 2 >= TARGET_SIZE) {
            longest /= 2
            sample *= 2
        }
        return sample
    }

    private fun circleCrop(source: Bitmap): Bitmap {
        val size = minOf(source.width, source.height)
        if (size <= 0) return source
        val left = (source.width - size) / 2
        val top = (source.height - size) / 2
        val output = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        val bounds = RectF(0f, 0f, size.toFloat(), size.toFloat())
        canvas.drawOval(bounds, paint)
        paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
        canvas.drawBitmap(
            source,
            Rect(left, top, left + size, top + size),
            bounds,
            paint
        )
        return output
    }
}
