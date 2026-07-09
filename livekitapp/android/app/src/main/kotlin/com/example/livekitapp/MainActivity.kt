package com.example.livekitapp

import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.telecom.TelecomManager
import android.content.IntentFilter
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Build

class MainActivity : FlutterActivity() {
    private val CHANNEL = "livekitapp/lockscreen"
    private var pendingUnlockResult: MethodChannel.Result? = null
    private var unlockReceiver: BroadcastReceiver? = null

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