package com.albertazzilabs.sneakscan

import android.os.Bundle
import android.provider.Settings
import androidx.activity.enableEdgeToEdge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    enableEdgeToEdge()
    super.onCreate(savedInstanceState)
  }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      "com.sneakerscanner/androidid",
    ).setMethodCallHandler { call, result ->
      if (call.method == "getAndroidId") {
        val androidId = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
        result.success(androidId)
      } else {
        result.notImplemented()
      }
    }
  }
}
