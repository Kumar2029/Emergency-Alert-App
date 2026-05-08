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
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN || keyCode == KeyEvent.KEYCODE_VOLUME_UP) {
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
        return super.onKeyDown(keyCode, event)
    }
}
