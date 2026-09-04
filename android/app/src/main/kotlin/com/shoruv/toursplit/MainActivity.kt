package com.shoruv.toursplit

import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.shoruv.toursplit/installer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isApkDownloaded" -> {
                    val filename = call.argument<String>("filename") ?: ""
                    if (filename.isEmpty()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val file = File(context.filesDir, "ota_update/$filename")
                    // Check if file exists and has size > 1MB
                    result.success(file.exists() && file.length() > 1024 * 1024)
                }
                "installApk" -> {
                    val filename = call.argument<String>("filename") ?: ""
                    val file = File(context.filesDir, "ota_update/$filename")
                    if (file.exists() && file.length() > 1024 * 1024) {
                        try {
                            val apkUri: Uri = FileProvider.getUriForFile(
                                context,
                                "${context.packageName}.ota_update_provider",
                                file
                            )
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(apkUri, "application/vnd.android.package-archive")
                                flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            context.startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INSTALL_ERROR", e.localizedMessage, null)
                        }
                    } else {
                        result.error("FILE_NOT_FOUND", "APK file not found on device", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
