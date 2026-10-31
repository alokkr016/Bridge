package io.github.alokkr016.otpbridge.ui

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.YuvImage
import android.net.Uri
import android.util.Log
import android.util.Size
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import com.google.zxing.*
import com.google.zxing.common.HybridBinarizer
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

private const val TAG = "PairingScreen"

@Composable
fun PairingScreen(
    onPaired: (deviceId: String, publicKey: ByteArray, ip: String, port: Int, displayName: String?, kind: String?, pairingToken: String?) -> Unit,
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    var hasCameraPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
                    PackageManager.PERMISSION_GRANTED
        )
    }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    val paired = remember { AtomicBoolean(false) }
    val frameCount = remember { mutableStateOf(0) }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        hasCameraPermission = granted
    }

    LaunchedEffect(Unit) {
        if (!hasCameraPermission) {
            permissionLauncher.launch(Manifest.permission.CAMERA)
        }
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Scan QR Code") },
        text = {
            Column {
                Text("Point your camera at the QR code on your Mac")
                Spacer(modifier = Modifier.height(16.dp))

                if (hasCameraPermission) {
                    AndroidView(
                        factory = { ctx ->
                            val previewView = PreviewView(ctx)
                            val cameraProviderFuture = ProcessCameraProvider.getInstance(ctx)
                            val analysisExecutor = Executors.newSingleThreadExecutor()

                            cameraProviderFuture.addListener({
                                val cameraProvider = cameraProviderFuture.get()
                                val preview = Preview.Builder().build().also {
                                    it.setSurfaceProvider(previewView.surfaceProvider)
                                }
                                val imageAnalysis = ImageAnalysis.Builder()
                                    .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888)
                                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                                    .build()

                                imageAnalysis.setAnalyzer(analysisExecutor) { imageProxy ->
                                    if (paired.get()) {
                                        imageProxy.close()
                                        return@setAnalyzer
                                    }

                                    val count = frameCount.value + 1
                                    frameCount.value = count

                                    try {
                                        val bitmap = toBitmap(imageProxy)
                                        if (bitmap == null) {
                                            Log.w(TAG, "Frame $count: failed to convert to bitmap")
                                            imageProxy.close()
                                            return@setAnalyzer
                                        }

                                        val w = bitmap.width
                                        val h = bitmap.height
                                        val pixels = IntArray(w * h)
                                        bitmap.getPixels(pixels, 0, w, 0, 0, w, h)
                                        bitmap.recycle()

                                        val source = luminanceSource(pixels, w, h)
                                        val binaryBitmap = BinaryBitmap(HybridBinarizer(source))
                                        val reader = MultiFormatReader()
                                        val result = reader.decode(binaryBitmap)
                                        val rawValue = result.text
                                        Log.i(TAG, "Frame $count: SCANNED -> $rawValue")

                                        if (rawValue.startsWith("otpbridge://") && paired.compareAndSet(false, true)) {
                                            val uri = Uri.parse(rawValue)
                                            val deviceId = uri.host ?: return@setAnalyzer
                                            val publicKeyB64 = uri.getQueryParameter("pk") ?: return@setAnalyzer
                                            val publicKeyPadded = publicKeyB64
                                                .replace("-", "+")
                                                .replace("_", "/")
                                                .let { if (it.length % 4 != 0) it + "=".repeat(4 - it.length % 4) else it }
                                            val publicKey = android.util.Base64.decode(publicKeyPadded, android.util.Base64.NO_WRAP)
                                            val ip = uri.getQueryParameter("ip") ?: return@setAnalyzer
                                            val port = uri.getQueryParameter("port")?.toIntOrNull() ?: 8420
                                            val displayName = uri.getQueryParameter("name")?.trim()?.takeIf { it.isNotEmpty() }
                                            val kind = uri.getQueryParameter("kind")?.trim()?.takeIf { it.isNotEmpty() }
                                            val pairingToken = uri.getQueryParameter("token")?.trim()?.takeIf { it.isNotEmpty() }
                                            Log.i(TAG, "Pairing: deviceId=$deviceId ip=$ip port=$port name=$displayName kind=$kind")
                                            onPaired(deviceId, publicKey, ip, port, displayName, kind, pairingToken)
                                        }
                                    } catch (_: NotFoundException) {
                                        // no QR in frame, keep scanning
                                    } catch (e: Exception) {
                                        Log.e(TAG, "Frame $count: scan error", e)
                                    } finally {
                                        imageProxy.close()
                                    }
                                }

                                try {
                                    cameraProvider.unbindAll()
                                    cameraProvider.bindToLifecycle(
                                        lifecycleOwner,
                                        CameraSelector.DEFAULT_BACK_CAMERA,
                                        preview,
                                        imageAnalysis
                                    )
                                    Log.i(TAG, "Camera bound successfully")
                                } catch (e: Exception) {
                                    Log.e(TAG, "Camera bind failed", e)
                                    errorMessage = "Camera error: ${e.message}"
                                }
                            }, ContextCompat.getMainExecutor(ctx))
                            previewView
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(300.dp)
                    )
                } else {
                    Text("Camera permission required")
                }

                errorMessage?.let {
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(it, color = MaterialTheme.colorScheme.error)
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        }
    )
}

private fun toBitmap(imageProxy: ImageProxy): Bitmap? {
    val planes = imageProxy.planes
    val yBuffer = planes[0].buffer
    val uBuffer = planes[1].buffer
    val vBuffer = planes[2].buffer

    val ySize = yBuffer.remaining()
    val uSize = uBuffer.remaining()
    val vSize = vBuffer.remaining()

    val nv21 = ByteArray(ySize + uSize + vSize)
    yBuffer.get(nv21, 0, ySize)
    vBuffer.get(nv21, ySize, vSize)
    uBuffer.get(nv21, ySize + vSize, uSize)

    val yuvImage = YuvImage(nv21, ImageFormat.NV21, imageProxy.width, imageProxy.height, null)
    val out = ByteArrayOutputStream()
    yuvImage.compressToJpeg(Rect(0, 0, imageProxy.width, imageProxy.height), 85, out)
    val bytes = out.toByteArray()

    val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return null

    val rotation = imageProxy.imageInfo.rotationDegrees
    return if (rotation != 0) {
        val matrix = Matrix()
        matrix.postRotate(rotation.toFloat())
        Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
    } else {
        bitmap
    }
}

private class luminanceSource(
    private val pixels: IntArray,
    private val w: Int,
    private val h: Int
) : LuminanceSource(w, h) {

    override fun getRow(y: Int, row: ByteArray?): ByteArray {
        val result = row ?: ByteArray(width)
        val offset = y * width
        for (x in 0 until width) {
            val p = pixels[offset + x]
            result[x] = (((p shr 16 and 0xFF) * 77 + (p shr 8 and 0xFF) * 150 + (p and 0xFF) * 29) shr 8).toByte()
        }
        return result
    }

    override fun getMatrix(): ByteArray {
        val result = ByteArray(width * height)
        for (i in pixels.indices) {
            val p = pixels[i]
            result[i] = (((p shr 16 and 0xFF) * 77 + (p shr 8 and 0xFF) * 150 + (p and 0xFF) * 29) shr 8).toByte()
        }
        return result
    }
}
