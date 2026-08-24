package de.eyev.flutter_skyle

import android.content.Context
import android.content.pm.PackageManager
import android.hardware.usb.UsbManager
import io.flutter.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * FlutterSkylePlugin: Per-engine glue for the Skyle EAP client.
 *
 * The USB transport itself is owned process-wide by [SkyleUsbHost] (started by
 * the accessibility service's service-ready hook, or - as an idempotent
 * fallback - on the first engine attach; the fallback is gated by the
 * [META_AUTO_START_USB_HOST] manifest meta-data, default true). This plugin
 * only:
 *  - offers the "configureTransport" method for the Dart fresh-start path,
 *  - offers "stopUsbHost" / "hasUsbPermission" for the Skyle Link handover
 *    and election flows,
 *  - tracks the engine's native callback-subscriber handle so
 *    onDetachedFromEngine can remove exactly this engine's subscription
 *    (the native fan-out keeps other engines' streams alive).
 */
class FlutterSkylePlugin: FlutterPlugin, MethodCallHandler {

  companion object {
    // Application-level manifest meta-data. Skyle X (and any app that should
    // own the tracker over USB) keeps the default true; SDK client apps that
    // only ever connect to a Skyle Link hub set it to false so an engine
    // attach never claims USB:
    //   <meta-data android:name="de.eyev.flutter_skyle.AUTO_START_USB_HOST"
    //              android:value="false" />
    private const val META_AUTO_START_USB_HOST = "de.eyev.flutter_skyle.AUTO_START_USB_HOST"

    // Skyle Link identity for SDK client apps (AUTO_START_USB_HOST=false):
    //   <meta-data android:name="de.eyev.flutter_skyle.APP_ID"
    //              android:value="my-aac-app" />        (default: packageName)
    //   <meta-data android:name="de.eyev.flutter_skyle.PRIORITY_TIER"
    //              android:value="1" />                 (default: 2; 0/skylex is reserved)
    private const val META_APP_ID = "de.eyev.flutter_skyle.APP_ID"
    private const val META_PRIORITY_TIER = "de.eyev.flutter_skyle.PRIORITY_TIER"

    private const val SKYLE_VENDOR_ID = 0x3729
    private const val SKYLE_PRODUCT_ID = 0x7333
  }

  private lateinit var methodChannel : MethodChannel
  private var context: Context? = null

  // This engine's native callback-subscriber handle, reported by its Dart
  // side after flutter_skyle_add_callbacks. 0 = none registered.
  private var subscriberHandle: Long = 0L

  private fun isAutoStartEnabled(context: Context): Boolean {
    return try {
      val info = context.packageManager.getApplicationInfo(context.packageName, PackageManager.GET_META_DATA)
      info.metaData?.getBoolean(META_AUTO_START_USB_HOST, true) ?: true
    } catch (e: Exception) {
      Log.w("FlutterSkylePlugin", "Failed to read $META_AUTO_START_USB_HOST meta-data: $e")
      true
    }
  }

  /**
   * True when the Skyle tracker is attached AND this app holds the platform
   * USB permission for it. No claim, no dialog - the Skyle Link election
   * eligibility check.
   */
  private fun hasUsbPermission(context: Context): Boolean {
    return try {
      val usbManager = context.getSystemService(Context.USB_SERVICE) as? UsbManager ?: return false
      val device = usbManager.deviceList.values.firstOrNull { it.vendorId == SKYLE_VENDOR_ID && it.productId == SKYLE_PRODUCT_ID }
      device != null && usbManager.hasPermission(device)
    } catch (e: Exception) {
      Log.w("FlutterSkylePlugin", "hasUsbPermission check failed: $e")
      false
    }
  }

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_skyle/usb")
    methodChannel.setMethodCallHandler(this)

    context = flutterPluginBinding.applicationContext

    // Idempotent: no-op when the accessibility service already started the
    // transport; brings it up for service-less setups (first run, tests).
    // SDK client apps opt out via the AUTO_START_USB_HOST meta-data and run
    // the Skyle Link supervisor as pure clients instead - never both, so the
    // Skyle X path (SkyleUsbHost publishes the skylex identity itself) is
    // never double-driven.
    if (isAutoStartEnabled(flutterPluginBinding.applicationContext)) {
      val started = SkyleUsbHost.start(flutterPluginBinding.applicationContext)
      Log.d("FlutterSkylePlugin", "Plugin attached to engine - SkyleUsbHost.start -> $started")
    } else {
      Log.d("FlutterSkylePlugin", "Plugin attached to engine - USB host auto-start disabled, enabling Skyle Link client supervisor")
      enableClientSupervisor(flutterPluginBinding.applicationContext)
    }
  }

  /**
   * Third-party SDK app path (AUTO_START_USB_HOST=false): publish the app's
   * identity from manifest meta-data and enable the automatic transport
   * supervisor. The supervisor dials the local Skyle Link hub on its own
   * (retrying until one appears). Idempotent - setIdentity/setSupervisorEnabled
   * may be called on every engine attach; the usb_capable re-push keeps the
   * election eligibility current.
   */
  private fun enableClientSupervisor(context: Context) {
    try {
      val meta = context.packageManager.getApplicationInfo(context.packageName, PackageManager.GET_META_DATA).metaData
      val appId = meta?.getString(META_APP_ID)?.takeIf { it.isNotBlank() } ?: context.packageName
      // Tier 0 (skylex) is claimed by convention - meta-data cannot take it.
      val tier = (meta?.getInt(META_PRIORITY_TIER, 2) ?: 2).coerceIn(1, 2)
      SkyleClientJni.setIdentity(appId, tier, hasUsbPermission(context))
      SkyleClientJni.setSupervisorEnabled(true)
      Log.d("FlutterSkylePlugin", "Skyle Link supervisor enabled (appId=$appId, tier=$tier)")
    } catch (e: Throwable) {
      // UnsatisfiedLinkError with an old libflutter_skyle.so, or anything
      // unexpected: the app then simply sees no tracker.
      Log.e("FlutterSkylePlugin", "Skyle Link supervisor setup failed: $e")
    }
  }

  private fun removeSubscriberIfSet() {
    if (subscriberHandle == 0L) return
    val clientPtr = SkyleClientJni.getInstance()
    if (clientPtr != 0L) {
      SkyleClientJni.removeSubscriber(clientPtr, subscriberHandle)
      Log.d("FlutterSkylePlugin", "Removed subscriber handle=$subscriberHandle")
    }
    subscriberHandle = 0L
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "configureTransport" -> {
        // Legacy Dart fresh-start path; now simply ensures the host is up.
        // Gated on the same meta-data as the attach auto-start so an SDK
        // client app's Dart layer can never claim USB / the skylex identity.
        val ctx = context
        result.success(ctx != null && isAutoStartEnabled(ctx) && SkyleUsbHost.start(ctx))
      }
      "reportSubscriberHandle" -> {
        // The engine's Dart side registered a native subscriber. On hot
        // restart a new isolate re-registers without the old one detaching -
        // reap the stale handle so the C thread cannot call into the dead
        // isolate's NativeCallables.
        val handle = (call.arguments as? Number)?.toLong() ?: 0L
        if (subscriberHandle != 0L && subscriberHandle != handle) {
          val clientPtr = SkyleClientJni.getInstance()
          if (clientPtr != 0L) {
            SkyleClientJni.removeSubscriber(clientPtr, subscriberHandle)
            Log.d("FlutterSkylePlugin", "Reaped stale subscriber handle=$subscriberHandle (hot restart)")
          }
        }
        subscriberHandle = handle
        result.success(true)
      }
      "clearSubscriberHandle" -> {
        // Orderly Dart-side destroy: the Dart side already removed the native
        // subscriber itself; just forget the bookkeeping.
        subscriberHandle = 0L
        result.success(true)
      }
      "stopUsbHost" -> {
        // Skyle Link handover: stop the hub, release USB, clear host
        // ownership. Best-effort and idempotent (see SkyleUsbHost.stop).
        SkyleUsbHost.stop()
        result.success(true)
      }
      "hasUsbPermission" -> {
        // Skyle Link election eligibility: tracker attached AND permission
        // held. Pure check - no interface claim, no permission dialog.
        val ctx = context
        result.success(ctx != null && hasUsbPermission(ctx))
      }
      else -> result.notImplemented()
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    methodChannel.setMethodCallHandler(null)

    // Remove ONLY this engine's callback subscriber before the Dart VM tears
    // down its NativeCallables. Other engines' subscriptions - and the
    // host-owned USB transport - stay untouched (this used to clear callbacks
    // process-wide and tear down the USB manager, killing eye tracking
    // whenever the main activity closed).
    removeSubscriberIfSet()
  }
}
