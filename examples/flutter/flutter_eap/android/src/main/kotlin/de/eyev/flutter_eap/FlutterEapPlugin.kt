package de.eyev.flutter_eap

import android.content.Context
import io.flutter.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * FlutterEapPlugin: Per-engine glue for the Skyle EAP client.
 *
 * The USB transport itself is owned process-wide by [EapUsbHost] (started by
 * the accessibility service's service-ready hook, or - as an idempotent
 * fallback - on the first engine attach). This plugin only:
 *  - offers the "configureTransport" method for the Dart fresh-start path,
 *  - tracks the engine's native callback-subscriber handle so
 *    onDetachedFromEngine can remove exactly this engine's subscription
 *    (the native fan-out keeps other engines' streams alive).
 */
class FlutterEapPlugin: FlutterPlugin, MethodCallHandler {

  private lateinit var methodChannel : MethodChannel
  private var context: Context? = null

  // This engine's native callback-subscriber handle, reported by its Dart
  // side after flutter_eap_add_callbacks. 0 = none registered.
  private var subscriberHandle: Long = 0L

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_eap/usb")
    methodChannel.setMethodCallHandler(this)

    context = flutterPluginBinding.applicationContext

    // Idempotent: no-op when the accessibility service already started the
    // transport; brings it up for service-less setups (first run, tests).
    val started = EapUsbHost.start(flutterPluginBinding.applicationContext)
    Log.d("FlutterEapPlugin", "Plugin attached to engine - EapUsbHost.start -> $started")
  }

  private fun removeSubscriberIfSet() {
    if (subscriberHandle == 0L) return
    val clientPtr = EapClientJni.getInstance()
    if (clientPtr != 0L) {
      EapClientJni.removeSubscriber(clientPtr, subscriberHandle)
      Log.d("FlutterEapPlugin", "Removed subscriber handle=$subscriberHandle")
    }
    subscriberHandle = 0L
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "configureTransport" -> {
        // Legacy Dart fresh-start path; now simply ensures the host is up.
        val ctx = context
        result.success(ctx != null && EapUsbHost.start(ctx))
      }
      "reportSubscriberHandle" -> {
        // The engine's Dart side registered a native subscriber. On hot
        // restart a new isolate re-registers without the old one detaching -
        // reap the stale handle so the C thread cannot call into the dead
        // isolate's NativeCallables.
        val handle = (call.arguments as? Number)?.toLong() ?: 0L
        if (subscriberHandle != 0L && subscriberHandle != handle) {
          val clientPtr = EapClientJni.getInstance()
          if (clientPtr != 0L) {
            EapClientJni.removeSubscriber(clientPtr, subscriberHandle)
            Log.d("FlutterEapPlugin", "Reaped stale subscriber handle=$subscriberHandle (hot restart)")
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
