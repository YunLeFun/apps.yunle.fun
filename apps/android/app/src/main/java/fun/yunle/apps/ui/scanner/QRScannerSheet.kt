package `fun`.yunle.apps.ui.scanner

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.widget.Toast
import androidx.activity.compose.LocalActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.CameraState
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.core.TorchState
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.edit
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.Observer
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.LocalLifecycleOwner
import `fun`.yunle.apps.NativeDestination
import `fun`.yunle.apps.WorkshopLink
import `fun`.yunle.apps.scanner.QrCodeDecoder
import `fun`.yunle.apps.scanner.ScanCandidate
import `fun`.yunle.apps.scanner.ScanImageError
import `fun`.yunle.apps.scanner.ScanImageException
import `fun`.yunle.apps.scanner.ScanParser
import `fun`.yunle.apps.scanner.ScanPurpose
import `fun`.yunle.apps.scanner.ScanResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.util.concurrent.Executors

private const val CAMERA_DENIED_PREF = "cameraPermissionPermanentlyDenied"

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun QRScannerSheet(
    onDestination: (NativeDestination) -> Unit,
    onWorkshopCode: (String) -> Unit,
    onOpenWebUrl: (String) -> Unit,
    onDismiss: () -> Unit,
    purpose: ScanPurpose = ScanPurpose.GENERAL,
) {
    val context = LocalContext.current
    val activity = LocalActivity.current
    val scope = rememberCoroutineScope()
    val clipboard = context.getSystemService(ClipboardManager::class.java)
    val permissionPreferences = remember(context) {
        context.getSharedPreferences("qr_scanner", Context.MODE_PRIVATE)
    }
    val hasCamera = remember(context) { context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY) }
    fun hasCameraPermission() = ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
        PackageManager.PERMISSION_GRANTED

    var cameraGranted by remember { mutableStateOf(hasCameraPermission()) }
    var cameraPermanentlyDenied by remember(permissionPreferences) {
        mutableStateOf(permissionPreferences.getBoolean(CAMERA_DENIED_PREF, false))
    }
    var cameraPermissionPending by rememberSaveable { mutableStateOf(false) }
    var manualMode by rememberSaveable { mutableStateOf(false) }
    var input by rememberSaveable { mutableStateOf("") }
    var payloads by rememberSaveable { mutableStateOf(emptyList<String>()) }
    var pickingPhoto by rememberSaveable { mutableStateOf(false) }
    var decodingPhoto by remember { mutableStateOf(false) }
    var scanError by remember { mutableStateOf<String?>(null) }
    var manualError by remember { mutableStateOf<String?>(null) }
    var closing by remember { mutableStateOf(false) }
    val candidates = remember(payloads, purpose) {
        payloads.map { ScanCandidate(it, ScanParser.parse(it, purpose)) }
    }

    fun dismiss() {
        if (closing) return
        closing = true
        onDismiss()
    }

    LifecycleResumeEffect(context) {
        cameraGranted = hasCameraPermission()
        if (cameraGranted && cameraPermanentlyDenied) {
            cameraPermanentlyDenied = false
            permissionPreferences.edit { remove(CAMERA_DENIED_PREF) }
        }
        onPauseOrDispose { }
    }
    val requestCamera = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        cameraPermissionPending = false
        cameraGranted = granted
        cameraPermanentlyDenied = !granted && activity != null &&
            !ActivityCompat.shouldShowRequestPermissionRationale(activity, Manifest.permission.CAMERA)
        permissionPreferences.edit { putBoolean(CAMERA_DENIED_PREF, cameraPermanentlyDenied) }
    }
    val pickPhoto = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        pickingPhoto = false
        if (uri != null && !closing) {
            decodingPhoto = true
            scope.launch {
                try {
                    val decoded = decodePickedPhoto(context.contentResolver, uri)
                    if (!closing) payloads = decoded
                } catch (error: ScanImageException) {
                    scanError = error.error.message
                } finally {
                    decodingPhoto = false
                }
            }
        }
    }

    fun launchDestination(destination: NativeDestination) {
        if (closing) return
        dismiss()
        onDestination(destination)
    }

    fun launchWebsite(url: String) {
        if (closing) return
        dismiss()
        onOpenWebUrl(url)
    }

    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(onDismissRequest = ::dismiss, sheetState = sheetState) {
        Column(
            modifier = Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("扫码或打开链接", Modifier.semantics { heading() }, style = MaterialTheme.typography.titleLarge)
            if (candidates.isNotEmpty()) {
                Text("识别到 ${candidates.size} 个二维码", Modifier.semantics { liveRegion = LiveRegionMode.Polite })
                OutlinedButton(onClick = {
                    payloads = emptyList()
                    scanError = null
                    manualMode = false
                }) {
                    Text("继续扫码")
                }
                for (candidate in candidates) {
                    ScannerCandidateCard(
                        candidate = candidate,
                        onDestination = ::launchDestination,
                        onOpenWebUrl = ::launchWebsite,
                        onCopy = { text ->
                            clipboard?.setPrimaryClip(ClipData.newPlainText("二维码文本", text))
                            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                                Toast.makeText(context, "已复制", Toast.LENGTH_SHORT).show()
                            }
                        },
                    )
                }
            } else {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(selected = !manualMode, onClick = { manualMode = false }, label = { Text("扫码") })
                    FilterChip(
                        selected = manualMode,
                        onClick = { manualMode = true },
                        enabled = !decodingPhoto,
                        label = { Text("手动输入") },
                    )
                }
                if (manualMode) {
                    OutlinedTextField(
                        value = input,
                        onValueChange = {
                            input = it
                            manualError = null
                        },
                        label = { Text("链接或 6 位工坊编号") },
                        placeholder = { Text("https://apps.yunle.fun/… 或 A2B3C4") },
                        singleLine = true,
                        isError = manualError != null,
                        supportingText = manualError?.let { message -> { ScannerError(message) } },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(onClick = {
                            val pasted = clipboard?.primaryClip?.getItemAt(0)?.text?.toString().orEmpty()
                            if (pasted.isBlank()) {
                                manualError = "剪贴板为空。"
                            } else {
                                input = pasted
                                manualError = null
                            }
                        }) { Text("从剪贴板粘贴") }
                        Button(enabled = input.isNotBlank(), onClick = {
                            when (val result = ScanParser.parse(input, purpose)) {
                                is ScanResult.Destination -> launchDestination(result.destination)
                                is ScanResult.Website -> launchWebsite(result.url)
                                is ScanResult.Text -> {
                                    val code = WorkshopLink.normalize(result.value)
                                    if (code != null && !closing) {
                                        dismiss()
                                        onWorkshopCode(code)
                                    } else {
                                        manualError = "请输入有效的链接或 6 位工坊编号。"
                                    }
                                }
                                ScanResult.UnsupportedWorkshop -> manualError = "请输入工坊链接或 6 位工坊编号。"
                                ScanResult.UnsupportedLink -> manualError = "无法打开此链接，请检查格式后重试。"
                            }
                        }) { Text("打开") }
                    }
                } else {
                    when {
                        decodingPhoto -> Row(
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            CircularProgressIndicator()
                            Text("正在识别图片…", Modifier.semantics { liveRegion = LiveRegionMode.Polite })
                        }
                        !hasCamera -> Text("此设备没有可用的相机。")
                        !cameraGranted -> {
                            Text("使用相机扫码需要相机权限。")
                            val openSettings = cameraPermanentlyDenied && activity != null
                            OutlinedButton(enabled = !cameraPermissionPending, onClick = {
                                if (openSettings) {
                                    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                                        .setData(Uri.fromParts("package", context.packageName, null))
                                    try {
                                        activity.startActivity(intent)
                                    } catch (_: ActivityNotFoundException) {
                                        scanError = "无法打开应用设置。"
                                    }
                                } else {
                                    cameraPermissionPending = true
                                    requestCamera.launch(Manifest.permission.CAMERA)
                                }
                            }) { Text(if (openSettings) "打开应用设置" else "允许使用相机") }
                        }
                        !pickingPhoto -> ScannerCamera { decoded ->
                            if (!closing && !manualMode && !pickingPhoto && !decodingPhoto && payloads.isEmpty()) {
                                scanError = null
                                payloads = decoded
                            }
                        }
                    }
                    OutlinedButton(enabled = !pickingPhoto && !decodingPhoto, onClick = {
                        scanError = null
                        pickingPhoto = true
                        try {
                            pickPhoto.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                        } catch (_: ActivityNotFoundException) {
                            pickingPhoto = false
                            scanError = "无法打开相册。"
                        }
                    }) { Text("从相册识别") }
                    scanError?.let { ScannerError(it) }
                }
            }
            TextButton(onClick = ::dismiss) { Text("关闭") }
        }
    }
}

@Composable
private fun ScannerCandidateCard(
    candidate: ScanCandidate,
    onDestination: (NativeDestination) -> Unit,
    onOpenWebUrl: (String) -> Unit,
    onCopy: (String) -> Unit,
) {
    Surface(shape = MaterialTheme.shapes.medium, color = MaterialTheme.colorScheme.surfaceContainerHighest) {
        Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(candidate.title, style = MaterialTheme.typography.titleMedium)
            SelectionContainer { Text(candidate.payload, style = MaterialTheme.typography.bodyMedium) }
            when (val result = candidate.result) {
                is ScanResult.Destination -> Button(onClick = { onDestination(result.destination) }) { Text("打开") }
                is ScanResult.Website -> OutlinedButton(onClick = { onOpenWebUrl(result.url) }) { Text("在浏览器中打开") }
                is ScanResult.Text -> OutlinedButton(onClick = { onCopy(result.value) }) { Text("复制文本") }
                ScanResult.UnsupportedWorkshop -> ScannerError("请选择工坊二维码或手动输入工坊编号。")
                ScanResult.UnsupportedLink -> ScannerError("此二维码中的链接无法安全打开。")
            }
        }
    }
}

@Composable
private fun ScannerError(message: String) {
    Text(message, Modifier.semantics { liveRegion = LiveRegionMode.Polite }, color = MaterialTheme.colorScheme.error)
}

@Composable
private fun ScannerCamera(onPayloads: (List<String>) -> Unit) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val latestOnPayloads by rememberUpdatedState(onPayloads)
    val previewView = remember(context) {
        PreviewView(context).apply {
            implementationMode = PreviewView.ImplementationMode.COMPATIBLE
            scaleType = PreviewView.ScaleType.FIT_CENTER
        }
    }
    var cameraError by remember { mutableStateOf<String?>(null) }
    var setTorch by remember { mutableStateOf<((Boolean) -> Unit)?>(null) }
    var torchEnabled by remember { mutableStateOf(false) }

    DisposableEffect(previewView, lifecycleOwner) {
        val analysisExecutor = Executors.newSingleThreadExecutor()
        val mainExecutor = ContextCompat.getMainExecutor(context)
        val preview = Preview.Builder().build().apply { setSurfaceProvider(previewView.surfaceProvider) }
        val analysis = ImageAnalysis.Builder().setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST).build()
        val providerFuture = ProcessCameraProvider.getInstance(context.applicationContext)
        var disposed = false
        var delivered = false
        var provider: ProcessCameraProvider? = null
        var stopObservingCamera: (() -> Unit)? = null
        analysis.setAnalyzer(analysisExecutor) { image ->
            val decoded = try {
                val plane = image.planes.firstOrNull() ?: return@setAnalyzer
                if (plane.pixelStride != 1) return@setAnalyzer
                val buffer = plane.buffer
                val bytes = ByteArray(buffer.remaining()).also { buffer.get(it) }
                QrCodeDecoder.decodeLumaFrame(bytes, image.width, image.height, plane.rowStride)
            } finally {
                image.close()
            }
            if (decoded.isNotEmpty()) {
                mainExecutor.execute {
                    if (!disposed && !delivered && lifecycleOwner.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) {
                        delivered = true
                        latestOnPayloads(decoded)
                    }
                }
            }
        }
        providerFuture.addListener({
            if (!disposed) {
                runCatching {
                    val cameraProvider = providerFuture.get().also { provider = it }
                    val selector = when {
                        cameraProvider.hasCamera(CameraSelector.DEFAULT_BACK_CAMERA) -> CameraSelector.DEFAULT_BACK_CAMERA
                        cameraProvider.hasCamera(CameraSelector.DEFAULT_FRONT_CAMERA) -> CameraSelector.DEFAULT_FRONT_CAMERA
                        else -> error("No camera available")
                    }
                    val camera = cameraProvider.bindToLifecycle(lifecycleOwner, selector, preview, analysis)
                    val cameraObserver = Observer<CameraState> { state ->
                        cameraError = state.error?.let { "相机暂不可用，可以选择相册或手动输入。" }
                    }
                    val torchObserver = Observer<Int> { state -> torchEnabled = state == TorchState.ON }
                    camera.cameraInfo.cameraState.observe(lifecycleOwner, cameraObserver)
                    if (camera.cameraInfo.hasFlashUnit()) {
                        camera.cameraInfo.torchState.observe(lifecycleOwner, torchObserver)
                        setTorch = { enabled -> camera.cameraControl.enableTorch(enabled) }
                    }
                    stopObservingCamera = {
                        camera.cameraInfo.cameraState.removeObserver(cameraObserver)
                        camera.cameraInfo.torchState.removeObserver(torchObserver)
                    }
                }.onFailure { cameraError = "无法启动相机，可以选择相册或手动输入。" }
            }
        }, mainExecutor)
        onDispose {
            disposed = true
            stopObservingCamera?.invoke()
            analysis.clearAnalyzer()
            provider?.unbind(preview, analysis)
            analysisExecutor.shutdown()
        }
    }

    AndroidView(
        factory = { previewView },
        modifier = Modifier.fillMaxWidth().height(240.dp).clip(MaterialTheme.shapes.medium),
    )
    cameraError?.let { ScannerError(it) }
    setTorch?.let { toggle ->
        OutlinedButton(enabled = cameraError == null, onClick = { toggle(!torchEnabled) }) {
            Text(if (torchEnabled) "关闭手电筒" else "打开手电筒")
        }
    }
}

private suspend fun decodePickedPhoto(resolver: ContentResolver, uri: Uri): List<String> = withContext(Dispatchers.IO) {
    try {
        val bytes = resolver.openInputStream(uri)?.use { stream ->
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                ensureActive()
                val remaining = QrCodeDecoder.MAX_IMAGE_BYTES - output.size()
                val count = stream.read(buffer, 0, minOf(buffer.size, remaining + 1))
                if (count == -1) break
                if (count > remaining) throw ScanImageException(ScanImageError.TOO_LARGE)
                output.write(buffer, 0, count)
            }
            output.toByteArray()
        } ?: throw ScanImageException(ScanImageError.INVALID_IMAGE)
        ensureActive()
        QrCodeDecoder.decodeImageBytes(bytes)
    } catch (_: IOException) {
        throw ScanImageException(ScanImageError.INVALID_IMAGE)
    } catch (_: SecurityException) {
        throw ScanImageException(ScanImageError.INVALID_IMAGE)
    }
}
