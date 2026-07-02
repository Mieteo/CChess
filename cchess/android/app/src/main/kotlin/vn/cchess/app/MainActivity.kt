package vn.cchess.app

import android.app.ActivityManager
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Offline Pikafish support: the Dart side needs to know where the
        // packaged engine "lib" executables were extracted, and how much RAM
        // the device has (capability gate before offering offline analysis).
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "cchess/pikafish",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "nativeLibraryDir" -> result.success(applicationInfo.nativeLibraryDir)
                "totalMemBytes" -> {
                    val memoryInfo = ActivityManager.MemoryInfo()
                    val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                    manager.getMemoryInfo(memoryInfo)
                    result.success(memoryInfo.totalMem)
                }
                else -> result.notImplemented()
            }
        }
    }
}
