package com.emergency.emergency_mobile

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent

class SOSAccessibilityService : AccessibilityService() {
    private var volumePressCount = 0
    private var lastPressTime: Long = 0

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Not required for key events
    }

    override fun onInterrupt() {
        // Required override, but no action needed
    }

    override fun onKeyEvent(event: KeyEvent?): Boolean {
        if (event != null && (event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN || event.keyCode == KeyEvent.KEYCODE_VOLUME_UP)) {
            // Only process the initial press down, ignore repeat events from holding
            if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                val currentTime = System.currentTimeMillis()
                
                // If more than 2 seconds since last press, start counting from 1 again
                if (currentTime - lastPressTime > 2000) {
                    volumePressCount = 1
                } else {
                    volumePressCount++
                }
                lastPressTime = currentTime
                
                // If 3 consecutive rapid presses occurred
                if (volumePressCount >= 3) {
                    volumePressCount = 0
                    triggerSOS()
                }
            }
            
            // We return false because we DO NOT want to completely consume the event and break the user's volume control entirely in the background.
            // It will still count our presses while letting the volume adjust normally.
            return false 
        }
        return super.onKeyEvent(event)
    }

    private fun triggerSOS() {
        // Launch the MainActivity
        val intent = Intent(this, MainActivity::class.java)
        // Ensure it acts as a new task, clears anything on top, and reuses the instance if possible
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        intent.putExtra("TRIGGER_SOS", true)
        startActivity(intent)
    }
}
