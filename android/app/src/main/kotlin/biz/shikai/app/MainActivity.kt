package biz.shikai.app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.Display
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterActivity() {
    private val UPDATER_CHANNEL = "biz.shikai.app/updater"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableHighRefreshRate()
    }

    override fun onResume() {
        super.onResume()
        enableHighRefreshRate()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCacheDirectory" -> {
                    result.success(cacheDir.absolutePath)
                }
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath.isNullOrEmpty()) {
                        result.error("INVALID_PATH", "File path cannot be null or empty", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val apkFile = File(filePath)
                        if (!apkFile.exists()) {
                            result.error("FILE_NOT_FOUND", "APK file does not exist at $filePath", null)
                            return@setMethodCallHandler
                        }

                        val uri: Uri = FileProvider.getUriForFile(
                            this,
                            "$packageName.fileprovider",
                            apkFile
                        )

                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }

                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("INSTALL_ERROR", e.localizedMessage, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Enables 120Hz / 144Hz high refresh rate display mode on supported devices.
     * Android Choreographer will sync Flutter VSYNC signals at 90fps/120fps/144fps.
     */
    private fun enableHighRefreshRate() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val window = window ?: return
                val display: Display? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    display
                } else {
                    @Suppress("DEPRECATION")
                    windowManager.defaultDisplay
                }

                if (display != null) {
                    val supportedModes = display.supportedModes
                    var bestMode: Display.Mode? = null
                    var maxRefreshRate = 60.0f

                    for (mode in supportedModes) {
                        if (mode.refreshRate > maxRefreshRate) {
                            maxRefreshRate = mode.refreshRate
                            bestMode = mode
                        }
                    }

                    val layoutParams = window.attributes
                    if (bestMode != null) {
                        layoutParams.preferredDisplayModeId = bestMode.modeId
                    }

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        layoutParams.preferredRefreshRate = maxRefreshRate
                    }

                    window.attributes = layoutParams
                }
            } catch (e: Exception) {
                // Graceful fallback if OEM restricts mode switching
            }
        }
    }
}
