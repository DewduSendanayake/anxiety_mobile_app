package com.example.anxiety_mobile_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import id.flutter.flutter_background_service.BackgroundService

/**
 * Listens for the system-wide ACTION_POWER_CONNECTED broadcast.
 *
 * WHY THIS EXISTS:
 * On this device class (confirmed via Service_Heartbeat gap analysis —
 * see check_heartbeat_gaps.py), the OS reliably kills the foreground
 * background service at or shortly after every charging-state transition,
 * despite isForegroundMode being correctly set. A Dart-level listener
 * inside the same isolate that's being killed cannot reliably react in
 * time. Registering this receiver at the manifest level means Android
 * itself wakes the app specifically for this event, independent of
 * whether the previous service instance is already dead.
 */
class PowerConnectedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_POWER_CONNECTED) {
            Log.d("PowerConnectedReceiver", "Power connected — restarting background service")
            try {
                val serviceIntent = Intent(context, BackgroundService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(serviceIntent)
                } else {
                    context.startService(serviceIntent)
                }
            } catch (e: Exception) {
                Log.e("PowerConnectedReceiver", "Failed to restart service: ${e.message}")
            }
        }
    }
}
