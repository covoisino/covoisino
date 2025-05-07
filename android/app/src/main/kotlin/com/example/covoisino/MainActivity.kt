package com.example.covoisino

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
  private val CHANNEL = "referral_link"
  private var initialLink: String? = null

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    initialLink = intent?.dataString
    MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
      when (call.method) {
        "getInitialLink" -> result.success(initialLink)
        else              -> result.notImplemented()
      }
    }
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    intent.dataString?.let { link ->
      MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, CHANNEL)
        .invokeMethod("onLinkReceived", link)
    }
  }
}