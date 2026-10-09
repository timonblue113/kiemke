
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Cầu nối Flutter <-> Google Code Scanner (Google Play Services).
// Dòng "package ..." được CI chèn tự động từ file MainActivity gốc.
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kiemkho/gscan")
            .setMethodCallHandler { call, result ->
                if (call.method == "scan") {
                    val options = GmsBarcodeScannerOptions.Builder().enableAutoZoom().build()
                    GmsBarcodeScanning.getClient(this, options)
                        .startScan()
                        .addOnSuccessListener { barcode -> result.success(barcode.rawValue) }
                        .addOnCanceledListener { result.success(null) }
                        .addOnFailureListener { e -> result.error("SCAN_ERROR", e.message, null) }
                } else {
                    result.notImplemented()
                }
            }
    }
}
