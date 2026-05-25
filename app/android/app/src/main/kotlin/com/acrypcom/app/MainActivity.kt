package com.acrypcom.app

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onResume() {
        super.onResume()
        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}
