package com.tsintsivadigital.maisum

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class SmsReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    // Reserved for OEM SMS routing when needed; telephony plugin handles listeners.
  }
}
