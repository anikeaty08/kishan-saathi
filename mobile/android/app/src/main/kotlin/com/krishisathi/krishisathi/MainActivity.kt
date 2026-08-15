package com.krishisathi.mobile

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (!BuildConfig.DEBUG && BuildConfig.FLAVOR == "production") {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }
}
