package com.example.livekitapp

import android.app.KeyguardManager
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.telecom.TelecomManager
import android.content.IntentFilter
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import android.app.PictureInPictureParams
import android.util.Rational
import android.content.res.Configuration
import io.flutter.plugin.common.MethodChannel
import android.os.Build
import android.os.Bundle
import android.view.WindowManager

class MainActivity : FlutterActivity() {
    companion object {
        const val ENGINE_ID = "livekitapp.main.engine"
        const val EXTRA_OPEN_ACTIVE_CALL = "open_active_call"
        const val CALL_FG_CHANNEL = "livekitapp/callforeground"
    }

    private val CHANNEL = "livekitapp/lockscreen"
    private var pendingUnlockResult: MethodChannel.Result? = null
    private var unlockReceiver: BroadcastReceiver? = null
    private val PIP_CHANNEL = "livekitapp/pip"
    private val RINGTONE_CHANNEL = "livekitapp/ringtone"

    private var isInPipMode = false
    private var isInCallState = false

    override fun provideFlutterEngine(context: Context): FlutterEngine {
        val cache = FlutterEngineCache.getInstance()
        cache.get(ENGINE_ID)?.let { return it }
        val engine = FlutterEngine(context.applicationContext)
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault()
        )
        cache.put(ENGINE_ID, engine)
        return engine
    }

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        // Blocks screenshots, screen recording, and app-switcher thumbnail preview.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
        super.onCreate(savedInstanceState)
        resetStaleIncomingCallChannel()
        handleOpenActiveCallIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleOpenActiveCallIntent(intent)
    }

    private fun handleOpenActiveCallIntent(intent: Intent?) {
        if (intent?.getBooleanExtra(EXTRA_OPEN_ACTIVE_CALL, false) != true) return
        intent.removeExtra(EXTRA_OPEN_ACTIVE_CALL)
        flutterEngine?.let {
            MethodChannel(it.dartExecutor.binaryMessenger, CALL_FG_CHANNEL)
                .invokeMethod("openActiveCall", null)
        }
    }

    // Notification channels are immutable once created on-device — if the
    // "Incoming Call" channel was ever created before ringtonePath was set
    // to the silent asset, Android keeps playing whatever sound (often the
    // phone's default ringtone) it was originally created with, no matter
    // what CallKitParams says now. Deleting it here forces flutter_callkit_incoming
    // to recreate it fresh — with the current (silent) config — the next
    // time an incoming call notification is shown, so only our custom
    // RingtoneService audio plays instead of two overlapping ringtones.
    private fun resetStaleIncomingCallChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val manager = getSystemService(NotificationManager::class.java)
                manager.notificationChannels
                    .filter { it.name == "Incoming Call" }
                    .forEach { manager.deleteNotificationChannel(it.id) }
            } catch (e: Exception) {
                android.util.Log.d("Callkit", "resetStaleIncomingCallChannel threw: $e")
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isDeviceLocked" -> {
                    val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
                    result.success(keyguardManager.isKeyguardLocked)
                }
                "showOverLockscreen" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        setShowWhenLocked(true)
                        setTurnScreenOn(true)
                    } else {
                        window.addFlags(
                            android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                            android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                        )
                    }
                    result.success(null)
                }
                "hideOverLockscreen" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        setShowWhenLocked(false)
                        setTurnScreenOn(false)
                    } else {
                        window.clearFlags(
                            android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                            android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                        )
                    }
                    result.success(null)
                }
                "forceClearTelecomCalls" -> {
                    forceClearTelecomCalls()
                    result.success(null)
                }
                "closeIncomingCallScreen" -> {
                    closeIncomingCallScreen()
                    result.success(null)
                }
                "waitForUnlock" -> {
                    val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
                    if (!keyguardManager.isKeyguardLocked) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    pendingUnlockResult = result
                    val receiver = object : BroadcastReceiver() {
                        override fun onReceive(context: Context, intent: Intent) {
                            if (intent.action == Intent.ACTION_USER_PRESENT) {
                                pendingUnlockResult?.success(null)
                                pendingUnlockResult = null
                                unregisterReceiver(this)
                                unlockReceiver = null
                            }
                        }
                    }
                    unlockReceiver = receiver
                    registerReceiver(receiver, IntentFilter(Intent.ACTION_USER_PRESENT))
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PIP_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "enterPip" -> {
                    result.success(enterPipMode())
                }
                "isPipSupported" -> {
                    result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                }
                "setCallActive" -> {
                    isInCallState = call.arguments as? Boolean ?: false
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, RINGTONE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startNativeRingtone" -> {
                    val intent = Intent(applicationContext, RingtoneService::class.java)
                    intent.action = RingtoneService.ACTION_START_APP
                    applicationContext.startForegroundService(intent)
                    result.success(null)
                }
                "stopNativeRingtone" -> {
                    val intent = Intent(applicationContext, RingtoneService::class.java)
                    intent.action = RingtoneService.ACTION_STOP
                    applicationContext.startService(intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CALL_FG_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val title = call.argument<String>("title") ?: "Ongoing call"
                    val video = call.argument<Boolean>("video") ?: false
                    val intent = Intent(applicationContext, CallForegroundService::class.java)
                    intent.action = CallForegroundService.ACTION_START
                    intent.putExtra(CallForegroundService.EXTRA_TITLE, title)
                    intent.putExtra(CallForegroundService.EXTRA_VIDEO, video)
                    applicationContext.startForegroundService(intent)
                    result.success(null)
                }
                "stop" -> {
                    val intent = Intent(applicationContext, CallForegroundService::class.java)
                    intent.action = CallForegroundService.ACTION_STOP
                    applicationContext.startService(intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }




    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (isInCallState) {
            enterPipMode()
        }
        flutterEngine?.let {
            MethodChannel(it.dartExecutor.binaryMessenger, PIP_CHANNEL)
                .invokeMethod("onUserLeaveHint", null)
        }
    }
    private fun forceClearTelecomCalls() {
    val telecomManager = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
    try {
        val result = telecomManager.endCall()
        android.util.Log.d("Callkit", "forceClearTelecomCalls: endCall() returned $result")
    } catch (e: Exception) {
        android.util.Log.d("Callkit", "forceClearTelecomCalls: endCall() threw $e")
    }
}
private fun enterPipMode(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val params = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(9, 14))
            .build()
        return try {
            enterPictureInPictureMode(params)
        } catch (e: Exception) {
            android.util.Log.d("PiP", "enterPipMode threw: $e")
            false
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        isInPipMode = isInPictureInPictureMode
        flutterEngine?.let {
            MethodChannel(it.dartExecutor.binaryMessenger, PIP_CHANNEL)
                .invokeMethod("onPipModeChanged", isInPictureInPictureMode)
        }
    }
private fun closeIncomingCallScreen() {
    val am = getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
    try {
        for (task in am.appTasks) {
            val className = task.taskInfo.topActivity?.className ?: continue
            android.util.Log.d("Callkit", "closeIncomingCallScreen: found task activity=$className")
            if (className.contains("CallkitIncomingActivity")) {
                task.finishAndRemoveTask()
                android.util.Log.d("Callkit", "closeIncomingCallScreen: finished task for $className")
            }
        }
    } catch (e: Exception) {
        android.util.Log.d("Callkit", "closeIncomingCallScreen threw: $e")
    }
}
    override fun onDestroy() {
        unlockReceiver?.let { unregisterReceiver(it) }
        super.onDestroy()
    }
}