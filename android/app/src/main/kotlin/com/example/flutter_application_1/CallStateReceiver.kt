package com.example.flutter_application_1

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.TelephonyManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import java.util.UUID

/**
 * Wakes up when a call state changes, even if the app is closed.
 * It reads only RINGING / IDLE. It never reads the phone number and never records.
 */
class CallStateReceiver : BroadcastReceiver() {

    companion object {
        const val CHANNEL_ID = "incoming_call_alerts"
        const val NOTIF_ID = 4001
        const val ACTION_DENY = "com.rahulks.voicedetector.ACTION_DENY"
        const val PREFS = "voice_detector_native"
        const val KEY_TOKEN = "pending_token"
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d("VDCall", "onReceive action=${intent.action} state=${intent.getStringExtra(TelephonyManager.EXTRA_STATE)}")
        if (intent.action == ACTION_DENY) {
            NotificationManagerCompat.from(context).cancel(NOTIF_ID)
            return
        }
        if (intent.action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) return

        when (intent.getStringExtra(TelephonyManager.EXTRA_STATE)) {
            TelephonyManager.EXTRA_STATE_RINGING -> showNotification(context)
            TelephonyManager.EXTRA_STATE_IDLE ->
                NotificationManagerCompat.from(context).cancel(NOTIF_ID)
        }
    }

    private fun showNotification(context: Context) {
        val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val enabled = flutterPrefs.getBoolean("flutter.liveCallDetection", false)
        Log.d("VDCall", "ringing, liveCallDetection=$enabled")
        if (!enabled) return

        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED
        ) {
            Log.d("VDCall", "notification permission missing")
            return
        }

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Incoming call alerts", NotificationManager.IMPORTANCE_HIGH)
            )
        }

        // One-time token so other apps cannot trigger recording by sending a fake intent.
        val token = UUID.randomUUID().toString()
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY_TOKEN, token).apply()

        val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT

        fun launch(action: String, requestCode: Int): PendingIntent {
            val i = Intent(context, MainActivity::class.java).apply {
                this.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("call_action", action)
                putExtra("call_token", token)
            }
            return PendingIntent.getActivity(context, requestCode, i, flags)
        }

        val denyIntent = PendingIntent.getBroadcast(
            context, 3,
            Intent(context, CallStateReceiver::class.java).apply { action = ACTION_DENY },
            flags
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("Incoming call detected")
            .setContentText("Allow Voice Detector to record audio for an AI voice check? Recording starts only if you tap Allow.")
            .setStyle(NotificationCompat.BigTextStyle().bigText(
                "Allow Voice Detector to record audio for an AI voice check? Recording starts only if you tap Allow."))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setOnlyAlertOnce(true)
            .setAutoCancel(true)
            .setContentIntent(launch("open", 1))
            .addAction(0, "Allow", launch("allow", 2))
            .addAction(0, "Don't allow", denyIntent)
            .build()

        manager.notify(NOTIF_ID, notification)
        Log.d("VDCall", "notification posted")
    }
}