package fr.adminfacile.app

import android.app.Activity
import android.content.Intent
import android.util.Log
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts.StartIntentSenderForResult
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val TAG = "AdminFacileScanner"
        private const val CHANNEL = "adminfacile/mlkit_document_scanner"
    }

    private var scannerResult: MethodChannel.Result? = null
    private var scanDiagnosticId: String? = null

    // Enregistrement inconditionnel recommandé par l'Activity Result API. Le
    // callback reste correctement rattaché lors d'une recréation d'Activity.
    private val scannerLauncher = registerForActivityResult(
        StartIntentSenderForResult()
    ) { activityResult ->
        handleScannerResult(activityResult.resultCode, activityResult.data)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "scan") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (scannerResult != null) {
                    result.error("SCAN_IN_PROGRESS", "Un scan est déjà en cours.", null)
                    return@setMethodCallHandler
                }
                val pageLimit = (call.argument<Int>("pageLimit") ?: 10).coerceIn(1, 10)
                scanDiagnosticId = UUID.randomUUID().toString().take(8)
                scannerResult = result
                logInfo("request", "pages=$pageLimit")
                launchMlKitScanner(pageLimit)
            }
    }

    private fun launchMlKitScanner(pageLimit: Int) {
        val options = try {
            logStep("options_create")
            GmsDocumentScannerOptions.Builder()
                .setGalleryImportAllowed(false)
                .setPageLimit(pageLimit)
                .setResultFormats(
                    GmsDocumentScannerOptions.RESULT_FORMAT_JPEG,
                    GmsDocumentScannerOptions.RESULT_FORMAT_PDF
                )
                .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL)
                .build()
                .also { logStep("options_ready") }
        } catch (error: Throwable) {
            finishScannerWithError("MLKIT_OPTIONS_FAILED", "options", error)
            return
        }

        val client = try {
            logStep("client_create")
            GmsDocumentScanning.getClient(options).also { logStep("client_ready") }
        } catch (error: Throwable) {
            finishScannerWithError("MLKIT_CLIENT_FAILED", "client", error)
            return
        }

        val intentTask = try {
            logStep("intent_sender_create")
            client.getStartScanIntent(this)
        } catch (error: Throwable) {
            finishScannerWithError("MLKIT_INTENT_FAILED", "intent_sender", error)
            return
        }

        intentTask
            .addOnSuccessListener { intentSender ->
                try {
                    logStep("intent_sender_ready")
                    scannerLauncher.launch(IntentSenderRequest.Builder(intentSender).build())
                    logStep("activity_launched")
                } catch (error: Throwable) {
                    finishScannerWithError("MLKIT_LAUNCH_FAILED", "activity_launch", error)
                }
            }
            .addOnFailureListener { error ->
                finishScannerWithError("MLKIT_UNAVAILABLE", "play_services", error)
            }
    }

    private fun handleScannerResult(resultCode: Int, data: Intent?) {
        logStep("activity_result", "resultCode=$resultCode data=${data != null}")
        val pending = scannerResult
        if (pending == null) {
            Log.w(TAG, "event=orphan_result resultCode=$resultCode")
            return
        }
        scannerResult = null

        if (resultCode == Activity.RESULT_CANCELED) {
            logInfo("cancelled")
            scanDiagnosticId = null
            pending.success(null)
            return
        }
        if (resultCode != Activity.RESULT_OK || data == null) {
            finishPendingWithError(
                pending,
                "MLKIT_SCAN_FAILED",
                "result",
                "resultCode=$resultCode data=${data != null}"
            )
            return
        }

        try {
            val scan = GmsDocumentScanningResult.fromActivityResultIntent(data)
            val pages = scan?.pages.orEmpty()
            if (pages.isEmpty()) {
                finishPendingWithError(pending, "MLKIT_EMPTY_RESULT", "decode", "pages=0")
                return
            }

            val outputDirectory = File(cacheDir, "document_scans").apply { mkdirs() }
            val stamp = System.currentTimeMillis()
            val paths = ArrayList<String>(pages.size)
            var failedPages = 0
            pages.forEachIndexed { index, page ->
                try {
                    val destination = File(outputDirectory, "scan_${stamp}_$index.jpg")
                    contentResolver.openInputStream(page.imageUri).use { input ->
                        requireNotNull(input) { "Image ML Kit illisible." }
                        FileOutputStream(destination).use { output -> input.copyTo(output) }
                    }
                    if (destination.length() <= 0L) error("Image ML Kit vide.")
                    paths.add(destination.absolutePath)
                } catch (error: Exception) {
                    failedPages += 1
                    Log.w(
                        TAG,
                        "id=$scanDiagnosticId event=page_copy_failed index=$index type=${error.javaClass.simpleName}"
                    )
                }
            }
            if (paths.isEmpty()) {
                finishPendingWithError(
                    pending,
                    "MLKIT_COPY_FAILED",
                    "copy_pages",
                    "failed=$failedPages"
                )
                return
            }

            var pdfPath: String? = null
            scan?.pdf?.uri?.let { uri ->
                try {
                    val destination = File(outputDirectory, "scan_$stamp.pdf")
                    contentResolver.openInputStream(uri).use { input ->
                        requireNotNull(input) { "PDF ML Kit illisible." }
                        FileOutputStream(destination).use { output -> input.copyTo(output) }
                    }
                    if (destination.length() > 0L) pdfPath = destination.absolutePath
                } catch (error: Exception) {
                    Log.w(
                        TAG,
                        "id=$scanDiagnosticId event=pdf_copy_failed type=${error.javaClass.simpleName}"
                    )
                }
            }

            logInfo(
                "success",
                "pages=${paths.size} failedPages=$failedPages nativePdf=${pdfPath != null}"
            )
            scanDiagnosticId = null
            pending.success(
                mapOf(
                    "imagePaths" to paths,
                    "pageCount" to paths.size,
                    "partialResult" to (failedPages > 0),
                    "pdfPath" to pdfPath
                )
            )
        } catch (error: Exception) {
            finishPendingWithError(
                pending,
                "MLKIT_RESULT_FAILED",
                "decode",
                error.javaClass.simpleName
            )
        }
    }

    private fun finishScannerWithError(code: String, stage: String, error: Throwable) {
        val pending = scannerResult ?: return
        scannerResult = null
        finishPendingWithError(pending, code, stage, error.javaClass.simpleName)
    }

    private fun finishPendingWithError(
        pending: MethodChannel.Result,
        code: String,
        stage: String,
        diagnostic: String
    ) {
        Log.e(
            TAG,
            "SCANNER_NATIVE id=$scanDiagnosticId failure=$stage code=$code type=$diagnostic"
        )
        pending.error(
            code,
            "Le scanner de documents est indisponible.",
            mapOf("diagnosticId" to scanDiagnosticId, "stage" to stage)
        )
        scanDiagnosticId = null
    }

    private fun logInfo(event: String, details: String = "") {
        Log.i(TAG, "id=$scanDiagnosticId event=$event $details".trim())
    }

    private fun logStep(step: String, details: String = "") {
        Log.i(TAG, "SCANNER_NATIVE id=$scanDiagnosticId step=$step $details".trim())
    }
}
