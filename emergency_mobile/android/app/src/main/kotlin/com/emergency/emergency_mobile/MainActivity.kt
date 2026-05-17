package com.emergency.emergency_mobile

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.telephony.SmsManager
import android.os.Build
import android.view.KeyEvent

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.emergency.app/hardware"
    private var methodChannel: MethodChannel? = null
    
    private var volumePressCount = 0
    private var lastPressTime: Long = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            if (call.method == "sendSms") {
                val phone = call.argument<String>("phone")
                val message = call.argument<String>("message")
                
                if (phone != null && message != null) {
                    try {
                        val smsManager: SmsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            this.getSystemService(SmsManager::class.java)
                        } else {
                            SmsManager.getDefault()
                        }
                        smsManager.sendTextMessage(phone, null, message, null, null)
                        result.success("SMS Sent Successfully")
                    } catch (e: Exception) {
                        result.error("SMS_FAILED", e.message, null)
                    }
                } else {
                    result.error("INVALID_ARGS", "Phone or Message is null", null)
                }
            } else if (call.method == "checkAccessibilityService") {
                result.success(isAccessibilityServiceEnabled())
            } else if (call.method == "openAccessibilitySettings") {
                val intent = android.content.Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS)
                intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                result.success(true)
            } else {
                result.notImplemented()
            }
        }
        
        // Handle case where AccessibilityService starts the app from scratch
        if (intent?.getBooleanExtra("TRIGGER_SOS", false) == true) {
            intent?.removeExtra("TRIGGER_SOS")
            // Give Flutter a moment to fully initialize its Dart isolate before sending the message
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                methodChannel?.invokeMethod("triggerHardwareSOS", null)
            }, 2000)
        }
    }
    
    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        // Handle case where app is already running but in the background
        if (intent.getBooleanExtra("TRIGGER_SOS", false)) {
            intent.removeExtra("TRIGGER_SOS")
            methodChannel?.invokeMethod("triggerHardwareSOS", null)
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN || keyCode == KeyEvent.KEYCODE_VOLUME_UP) {
            if (event?.repeatCount == 0) {
                val currentTime = System.currentTimeMillis()
                if (currentTime - lastPressTime > 2000) {
                    volumePressCount = 1
                } else {
                    volumePressCount++
                }
                lastPressTime = currentTime
                
                if (volumePressCount >= 3) {
                    volumePressCount = 0
                    methodChannel?.invokeMethod("triggerHardwareSOS", null)
                }
            }
            return true // Consume the event so system volume panel doesn't intercept it
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN || keyCode == KeyEvent.KEYCODE_VOLUME_UP) {
            return true // Consume the event
        }
        return super.onKeyUp(keyCode, event)
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        var accessibilityEnabled = 0
        val service = packageName + "/" + SOSAccessibilityService::class.java.canonicalName
        try {
            accessibilityEnabled = android.provider.Settings.Secure.getInt(
                applicationContext.contentResolver,
                android.provider.Settings.Secure.ACCESSIBILITY_ENABLED
            )
        } catch (e: android.provider.Settings.SettingNotFoundException) {
            // Default to false if setting is not found
        }
        val textUtils = android.text.TextUtils.SimpleStringSplitter(':')
        if (accessibilityEnabled == 1) {
            val settingValue = android.provider.Settings.Secure.getString(
                applicationContext.contentResolver,
                android.provider.Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            )
            if (settingValue != null) {
                textUtils.setString(settingValue)
                while (textUtils.hasNext()) {
                    val accessibilityService = textUtils.next()
                    if (accessibilityService.equals(service, ignoreCase = true)) {
                        return true
                    }
                }
            }
        }
        return false
    }
}
