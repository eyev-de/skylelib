package de.eyev.flutter_eap

import android.content.Context
import androidx.annotation.NonNull

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.Log


/**
 * FlutterEapPlugin - Android USB bridge for flutter_eap
 *
 * This plugin handles:
 * - USB device connection/disconnection
 * - USB bulk transfers (read/write)
 * - Feeding received USB data to Dart FFI layer
 *
 * The actual EAP protocol parsing happens in the C library via FFI.
 * This plugin is just a USB I/O bridge.
 * 
 * IMPORTANT: This plugin may be attached to multiple Flutter engines (main app + overlays).
 * USB and native client initialization is only done once globally (from the first engine),
 * while secondary engines (overlays) only get method channel setup.
 */
class FlutterEapPlugin: FlutterPlugin, MethodCallHandler {

  companion object {
    // Global static state - shared across all plugin instances
    private var globalUsbManager: UsbEndpointManager? = null
    private var isGloballyInitialized = false
    private var isTransportConfigured = false
    private var primaryMethodChannel: MethodChannel? = null
  }

  private lateinit var methodChannel : MethodChannel
  private var context: Context? = null
  private var isPrimaryInstance = false

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_eap/usb")
    methodChannel.setMethodCallHandler(this)

    context = flutterPluginBinding.applicationContext

    // Only initialize USB manager once globally (from first engine)
    // NOTE: Transport configuration is deferred until Dart signals readiness
    // This prevents race condition where C background thread starts before Dart callbacks are set
    if (!isGloballyInitialized) {
      isPrimaryInstance = true
      primaryMethodChannel = methodChannel
      initializeUsbManager()
      Log.d("FlutterEapPlugin", "Plugin attached to PRIMARY engine - USB manager initialized (transport deferred)")
    } else {
      Log.d("FlutterEapPlugin", "Plugin attached to SECONDARY engine (overlay) - skipping USB init")
    }
  }

  private fun initializeUsbManager() {
    if (globalUsbManager != null) {
      Log.d("FlutterEapPlugin", "USB manager already initialized globally")
      return
    }

    try {
      // Create USB manager with callbacks - uses primary method channel
      globalUsbManager = UsbEndpointManager(
        context!!,
        onDeviceConnected = { device ->
          Log.d("FlutterEapPlugin", "USB device connected: ${device.deviceName}")
          primaryMethodChannel?.invokeMethod("onUsbConnected", mapOf(
            "vendorId" to device.vendorId,
            "productId" to device.productId,
            "deviceName" to device.deviceName
          ))
        },
        onDeviceDisconnected = { device ->
          Log.d("FlutterEapPlugin", "USB device disconnected: ${device.deviceName}")
          primaryMethodChannel?.invokeMethod("onUsbDisconnected", null)
        },
        onOpenedSession = {
          Log.d("FlutterEapPlugin", "USB session opened")
          primaryMethodChannel?.invokeMethod("onUsbSessionOpened", null)
        }
      )

      globalUsbManager?.registerReceiver()

      // NOTE: Transport configuration is deferred until Dart calls "configureTransport"
      // This prevents race condition where C background thread starts before Dart callbacks are set

      isGloballyInitialized = true
      Log.d("FlutterEapPlugin", "USB manager initialized, waiting for Dart to signal readiness")
    } catch (e: Exception) {
      Log.e("FlutterEapPlugin", "Error initializing USB manager: ${e.message}", e)
    }
  }

  /**
   * Configure native transport - called by Dart after callbacks are registered
   * This starts the C background thread which will detect USB and begin handshake
   *
   * IMPORTANT: USB callbacks must be registered BEFORE starting the background thread
   * to prevent race condition where the thread tries to read/write before callbacks are set.
   */
  private fun configureTransport(): Boolean {
    if (isTransportConfigured) {
      Log.d("FlutterEapPlugin", "Transport already configured")
      return true
    }

    if (globalUsbManager == null) {
      Log.e("FlutterEapPlugin", "Cannot configure transport: USB manager not initialized")
      return false
    }

    try {
      // Step 1: Get singleton client instance
      val clientPtr = EapClientJni.getInstance()
      if (clientPtr == 0L) {
        Log.e("FlutterEapPlugin", "Failed to get singleton client instance")
        return false
      }

      // Step 2: Register USB callbacks FIRST (before starting background thread)
      // This prevents race condition where background thread detects USB device
      // and tries to read/write before the JNI callbacks are registered.
      EapClientJni.setUsbWriteCallback(clientPtr, globalUsbManager!!)
      Log.d("FlutterEapPlugin", "USB write callback registered (clientPtr=$clientPtr)")

      // Step 3: NOW configure transport (this starts the background thread)
      val transportClientPtr = EapClientJni.createWithTransport()
      if (transportClientPtr != 0L && transportClientPtr == clientPtr) {
        Log.d("FlutterEapPlugin", "Transport configured successfully, background thread started")
        isTransportConfigured = true
        return true
      } else {
        Log.e("FlutterEapPlugin", "Failed to configure transport (returned=$transportClientPtr, expected=$clientPtr)")
      }
    } catch (e: Exception) {
      Log.e("FlutterEapPlugin", "Error configuring transport: ${e.message}", e)
    }
    return false
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "configureTransport" -> {
        // Called by Dart after callbacks are registered
        // This starts the C background thread which will detect USB and begin handshake
        val success = configureTransport()
        result.success(success)
      }
      else -> result.notImplemented()
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    methodChannel.setMethodCallHandler(null)

    // Clear Dart callbacks before the Dart VM tears down NativeCallables.
    // Without this the C background thread can call a closed NativeCallable
    // and trigger DLRT_GetFfiCallbackMetadata -> abort().
    val clientPtr = EapClientJni.getInstance()
    if (clientPtr != 0L) {
      EapClientJni.clearCallbacks(clientPtr)
      Log.d("FlutterEapPlugin", "Dart callbacks cleared on engine detach")
    }

    // Only cleanup global resources if this is the primary instance being detached
    if (isPrimaryInstance) {
      Log.d("FlutterEapPlugin", "PRIMARY plugin detached from engine - cleaning up global resources")
      globalUsbManager?.unregisterReceiver()
      globalUsbManager = null
      primaryMethodChannel = null
      isGloballyInitialized = false
      isTransportConfigured = false
    } else {
      Log.d("FlutterEapPlugin", "Secondary plugin detached from engine (overlay)")
    }
  }
}
