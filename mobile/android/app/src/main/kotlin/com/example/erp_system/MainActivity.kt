package com.example.erp_system

import android.media.AudioAttributes
import android.media.SoundPool
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var confirmationPool: SoundPool? = null
    private var confirmationId = 0
    private var confirmationReady = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Preload an original chime; never delay checkout waiting for audio.
        try {
            val pool = SoundPool.Builder().setMaxStreams(1)
                .setAudioAttributes(AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                .build()
            confirmationPool = pool
            pool.setOnLoadCompleteListener { _, id, status ->
                confirmationReady = status == 0 && id == confirmationId
            }
            confirmationId = pool.load(this, R.raw.sale_confirmation, 1)
        } catch (_: RuntimeException) {
            confirmationReady = false
            confirmationPool?.release()
            confirmationPool = null
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "erp/confirmation")
            .setMethodCallHandler { call, result ->
                if (call.method != "success") {
                    result.notImplemented()
                } else {
                    try {
                        val played = confirmationReady &&
                            (confirmationPool?.play(confirmationId, 0.7f, 0.7f, 1, 0, 1f) ?: 0) != 0
                        result.success(played)
                    } catch (_: RuntimeException) {
                        result.success(false)
                    }
                }
            }
    }

    override fun onDestroy() {
        confirmationReady = false
        confirmationPool?.release()
        confirmationPool = null
        super.onDestroy()
    }
}
