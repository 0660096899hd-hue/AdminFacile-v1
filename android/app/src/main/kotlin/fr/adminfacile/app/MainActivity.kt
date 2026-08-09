package fr.adminfacile.app

import android.app.Activity
import android.content.Intent
import android.content.IntentSender
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private var scannerResult: MethodChannel.Result? = null
    private val scannerRequestCode = 1900

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "adminfacile/mlkit_document_scanner"
        ).setMethodCallHandler { call, result ->
            if (call.method != "scan") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (scannerResult != null) {
                result.error("SCAN_IN_PROGRESS", "Un scan est déjà en cours.", null)
                return@setMethodCallHandler
            }
            val pageLimit = (call.argument<Int>("pageLimit") ?: 10).coerceIn(1, 10)
            scannerResult = result
            launchMlKitScanner(pageLimit)
        }
    }

    private fun launchMlKitScanner(pageLimit: Int) {
        val options = GmsDocumentScannerOptions.Builder()
            .setGalleryImportAllowed(false)
            .setPageLimit(pageLimit)
            .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG)
            .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL)
            .build()

        GmsDocumentScanning.getClient(options)
            .getStartScanIntent(this)
            .addOnSuccessListener { intentSender: IntentSender ->
                try {
                    startIntentSenderForResult(
                        intentSender,
                        scannerRequestCode,
                        null,
                        0,
                        0,
                        0,
                        null
                    )
                } catch (error: Exception) {
                    finishScannerWithError("MLKIT_LAUNCH_FAILED", error)
                }
            }
            .addOnFailureListener { error ->
                finishScannerWithError("MLKIT_UNAVAILABLE", error)
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != scannerRequestCode) return
        val pending = scannerResult ?: return
        scannerResult = null

        if (resultCode == Activity.RESULT_CANCELED) {
            pending.success(null)
            return
        }
        if (resultCode != Activity.RESULT_OK) {
            pending.error("MLKIT_SCAN_FAILED", "Résultat scanner invalide.", null)
            return
        }

        try {
            val pages = GmsDocumentScanningResult
                .fromActivityResultIntent(data)
                ?.pages
                .orEmpty()
            if (pages.isEmpty()) {
                pending.error("MLKIT_EMPTY_RESULT", "Aucune page retournée.", null)
                return
            }

            val stamp = System.currentTimeMillis()
            val paths = ArrayList<String>(pages.size)
            var partialResult = false
            pages.forEachIndexed { index, page ->
                try {
                    val destination = File(cacheDir, "mlkit_scan_${stamp}_$index.jpg")
                    contentResolver.openInputStream(page.imageUri).use { input ->
                        requireNotNull(input) { "Image ML Kit illisible." }
                        FileOutputStream(destination).use { output -> input.copyTo(output) }
                    }
                    paths.add(destination.path)
                } catch (_: Exception) {
                    partialResult = true
                }
            }
            if (paths.isEmpty()) {
                pending.error("MLKIT_COPY_FAILED", "Aucune page lisible.", null)
                return
            }
            pending.success(mapOf(
                "imagePaths" to paths,
                "pageCount" to paths.size,
                "partialResult" to partialResult
            ))
        } catch (error: Exception) {
            pending.error("MLKIT_COPY_FAILED", error.message, error.toString())
        }
    }

    private fun finishScannerWithError(code: String, error: Exception) {
        scannerResult?.error(code, error.message, error.toString())
        scannerResult = null
    }
}
