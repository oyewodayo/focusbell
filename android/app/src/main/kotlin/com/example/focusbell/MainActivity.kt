package co.ibeep.focusbell

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "focusbell/recording_live"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val title = call.argument<String>("title") ?: "Voice note"
                    val intent = Intent(this, RecordingLiveService::class.java).apply {
                        action = RecordingLiveService.ACTION_START
                        putExtra(RecordingLiveService.EXTRA_TITLE, title)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
                    result.success(null)
                }
                "stop" -> {
                    startService(Intent(this, RecordingLiveService::class.java).apply {
                        action = RecordingLiveService.ACTION_STOP
                    })
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}