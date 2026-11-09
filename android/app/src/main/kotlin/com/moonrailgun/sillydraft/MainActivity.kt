package com.moonrailgun.sillydraft

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "sillydraft/workspace",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "nativeLibraryDir" -> result.success(applicationInfo.nativeLibraryDir)
                "filesDir" -> result.success(filesDir.absolutePath)
                "cacheDir" -> result.success(cacheDir.absolutePath)
                "documentsRoot" -> {
                    val dir = File(
                        Environment.getExternalStoragePublicDirectory(
                            Environment.DIRECTORY_DOCUMENTS,
                        ),
                        "sillydraft",
                    )
                    dir.mkdirs()
                    result.success(dir.absolutePath)
                }
                "hasAllFilesAccess" -> result.success(hasAllFilesAccess())
                "requestAllFilesAccess" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        startActivity(
                            Intent(
                                Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                                Uri.parse("package:$packageName"),
                            ),
                        )
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "extractRootfs" -> {
                    val archive = call.argument<String>("archive")
                    val target = call.argument<String>("target")
                    if (archive == null || target == null) {
                        result.error("bad_args", "archive and target are required", null)
                    } else {
                        Thread {
                            try {
                                RootfsExtractor.extract(File(archive), File(target))
                                runOnUiThread { result.success(true) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error(
                                        "extract_failed",
                                        e.message ?: e.toString(),
                                        null,
                                    )
                                }
                            }
                        }.start()
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun hasAllFilesAccess(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.R ||
            Environment.isExternalStorageManager()
}
