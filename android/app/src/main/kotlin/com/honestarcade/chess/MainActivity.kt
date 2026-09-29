package com.honestarcade.chess

import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// lib/platform/platform_channel.dart's platformChannelName is the same.
private const val CHANNEL = "honestchess/platform"

class MainActivity : FlutterActivity() {
    private var sound: SoundBridge? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // The volume keys set the media volume the game's sounds play at (#96).
        volumeControlStream = AudioManager.STREAM_MUSIC
    }

    // The app's whole Android surface (#80): the private files directory the
    // store saves into, opening an https link in the browser, and the
    // installed version; and, on a second channel in SoundBridge.kt, the
    // sounds (#96). None of it needs a permission, and
    // test/guards/platform_surface_test.dart keeps each channel to exactly
    // its own methods.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val bridge = SoundBridge(applicationContext)
        bridge.attach(flutterEngine.dartExecutor.binaryMessenger)
        sound = bridge
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "filesDir" -> filesDir(result)
                    "openUrl" -> result.success(openUrl(urlArgument(call.arguments)))
                    "appVersion" -> appVersion(result)
                    else -> result.notImplemented()
                }
            }
    }

    override fun onPause() {
        // The loop never plays behind another app; Dart restarts it on return.
        sound?.pauseMusic()
        super.onPause()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        sound?.release()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        sound?.release()
        sound = null
        super.onDestroy()
    }

    private fun filesDir(result: MethodChannel.Result) {
        try {
            result.success(applicationContext.filesDir.absolutePath)
        } catch (e: Exception) {
            result.error("unavailable", e.message, null)
        }
    }

    // The arguments are a map from Dart; anything else carries no link.
    private fun urlArgument(arguments: Any?): String? =
        (arguments as? Map<*, *>)?.get("url") as? String

    // Dart refuses anything but https already; this checks again so the
    // Android side never opens another scheme whoever calls it. Any failure,
    // including no app to open it, answers false rather than crashing.
    private fun openUrl(url: String?): Boolean {
        if (url == null) return false
        return try {
            val uri = Uri.parse(url)
            if (uri.scheme != "https" || uri.host.isNullOrEmpty()) return false
            val intent = Intent(Intent.ACTION_VIEW, uri)
                .addCategory(Intent.CATEGORY_BROWSABLE)
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun appVersion(result: MethodChannel.Result) {
        try {
            val info = packageInfo()
            val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                info.versionCode.toLong()
            }
            result.success(mapOf("name" to info.versionName, "code" to code))
        } catch (e: Exception) {
            result.error("unavailable", e.message, null)
        }
    }

    private fun packageInfo(): PackageInfo =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, 0)
        }
}
