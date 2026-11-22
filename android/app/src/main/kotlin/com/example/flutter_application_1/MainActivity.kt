package com.example.flutter_application_1

import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "voice_detector/call_action"
    private var channel: MethodChannel? = null
    private var pendingAction: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingAction = extractAction(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialAction" -> {
                    result.success(pendingAction)
                    pendingAction = null
                }
                "startService" -> {
                    ContextCompat.startForegroundService(
                        this, Intent(this, CallMonitorService::class.java))
                    result.success(true)
                }
                "stopService" -> {
                    stopService(Intent(this, CallMonitorService::class.java))
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        extractAction(intent)?.let { channel?.invokeMethod("onAction", it) }
    }

    /** Returns the action only if the one-time token from our receiver matches. */
    private fun extractAction(intent: Intent?): String? {
        val action = intent?.getStringExtra("call_action") ?: return null
        val token = intent.getStringExtra("call_token")
        intent.removeExtra("call_action")
        intent.removeExtra("call_token")

        val prefs = getSharedPreferences(CallStateReceiver.PREFS, Context.MODE_PRIVATE)
        val saved = prefs.getString(CallStateReceiver.KEY_TOKEN, null)
        if (token == null || token != saved) return null
        if (action == "allow") prefs.edit().remove(CallStateReceiver.KEY_TOKEN).apply() // single use
        return action
    }
}