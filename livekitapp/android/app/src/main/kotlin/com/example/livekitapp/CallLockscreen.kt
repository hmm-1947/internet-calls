package com.example.livekitapp

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.os.Build
import android.view.WindowManager

object CallLockscreen {

    @Volatile
    private var callActive: Boolean = false

    fun isCallActive(): Boolean = callActive

    fun setCallActive(value: Boolean) {
        callActive = value
    }

    fun isDeviceLocked(context: Context): Boolean {
        val keyguardManager =
            context.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager ?: return false
        return keyguardManager.isKeyguardLocked
    }

    fun isDeviceInteractive(context: Context): Boolean {
        val powerManager =
            context.getSystemService(Context.POWER_SERVICE) as? android.os.PowerManager
                ?: return true
        return powerManager.isInteractive
    }

    fun apply(activity: Activity, show: Boolean) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                activity.setShowWhenLocked(show)
                activity.setTurnScreenOn(show)
            } else {
                val flags = WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                if (show) {
                    activity.window.addFlags(flags)
                } else {
                    activity.window.clearFlags(flags)
                }
            }
        } catch (e: Exception) {
            android.util.Log.d("CallLockscreen", "apply threw: $e")
        }
    }
}
