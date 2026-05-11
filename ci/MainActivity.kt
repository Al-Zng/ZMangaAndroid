package __PACKAGE__

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.webkit.CookieManager

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ─── Cookie Bridge: يُرجع كوكيز Android WebView (بما فيها cf_clearance) ───
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "zmanga/cookies"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCookies" -> {
                    val url = call.argument<String>("url") ?: ""
                    val cookies = try {
                        CookieManager.getInstance().getCookie(url) ?: ""
                    } catch (e: Exception) {
                        ""
                    }
                    result.success(cookies)
                }
                else -> result.notImplemented()
            }
        }
    }
}
