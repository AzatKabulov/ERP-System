package com.example.erp_system

import android.app.Activity
import android.graphics.BitmapFactory
import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/** Explicit photo OCR only. No image upload, no model download at runtime. */
class LabelTextReader(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private val executor = Executors.newSingleThreadExecutor()
    private var busy = false

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "read") { result.notImplemented(); return }
        val bytes = call.arguments as? ByteArray
        if (bytes == null || bytes.isEmpty() || bytes.size > 12 * 1024 * 1024) {
            result.error("invalid_image", "Invalid image", null); return
        }
        if (busy) { result.error("busy", "Recognition in progress", null); return }
        busy = true
        executor.execute {
            var file: File? = null
            try {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                require(bounds.outWidth > 0 && bounds.outHeight > 0 &&
                    bounds.outWidth.toLong() * bounds.outHeight <= 16_000_000)
                file = File.createTempFile("erp-label-", ".jpg", activity.cacheDir)
                file.writeBytes(bytes)
                val image = InputImage.fromFilePath(activity, Uri.fromFile(file))
                val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
                val temporary = file
                recognizer.process(image)
                    .addOnSuccessListener { text ->
                        busy = false
                        result.success(text.text.take(20000))
                    }
                    .addOnFailureListener {
                        busy = false
                        result.error("ocr_failed", "Could not read image", null)
                    }
                    .addOnCompleteListener { recognizer.close(); temporary.delete() }
            } catch (_: Exception) {
                file?.delete()
                activity.runOnUiThread {
                    busy = false
                    result.error("ocr_failed", "Could not read image", null)
                }
            }
        }
    }

    fun close() { executor.shutdown() }
}
