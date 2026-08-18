package de.eyev.flutter_eap

import android.content.Context
import io.flutter.Log

/**
 * Process-wide owner of the Skyle USB transport, independent of any Flutter
 * engine.
 *
 * Started by the accessibility service (via the app's service-ready hook) so
 * the eye-tracker link exists before - and survives independent of - every
 * Flutter engine. FlutterEapPlugin.onAttachedToEngine calls start() as an
 * idempotent fallback for setups without the service (first run before the
 * accessibility permission is granted, plain plugin consumers).
 *
 * There is deliberately no stop/teardown API: the transport lives as long as
 * the process. Once started, setHostOwned(true) makes Dart-initiated
 * destroy/disconnect no-ops in the native bridge.
 */
object EapUsbHost {
    private const val TAG = "EapUsbHost"

    private val lock = Any()

    @Volatile
    var isStarted: Boolean = false
        private set

    // Kept alive for the process lifetime; the native bridge holds a JNI
    // global ref to it as the transport callback.
    @Suppress("unused")
    private var usbManager: UsbEndpointManager? = null

    /**
     * Idempotent transport bring-up. Returns true when the transport is
     * running (already or newly started). Must be called from the main thread
     * (UsbEndpointManager posts on the main looper; both call sites - the
     * accessibility service hook and plugin attach - run there).
     */
    @JvmStatic
    fun start(context: Context): Boolean {
        synchronized(lock) {
            if (isStarted) {
                return true
            }

            val appContext = context.applicationContext

            val clientPtr = EapClientJni.getInstance()
            if (clientPtr == 0L) {
                Log.e(TAG, "start: failed to get native client instance")
                return false
            }

            // The old onUsbConnected/onUsbDisconnected/onUsbSessionOpened
            // method-channel notifications had no Dart listener - log only.
            val manager = UsbEndpointManager(
                appContext,
                onDeviceConnected = { device -> Log.d(TAG, "USB device connected: ${device.deviceName}") },
                onDeviceDisconnected = { device -> Log.d(TAG, "USB device disconnected: ${device.deviceName}") },
                onOpenedSession = { Log.d(TAG, "USB session opened") },
            )

            // Order is load-bearing: the JNI transport callback must be
            // registered BEFORE createWithTransport starts the C threads,
            // or the background thread could read/write with no callback.
            EapClientJni.setUsbWriteCallback(clientPtr, manager)
            manager.registerReceiver()

            val transportPtr = EapClientJni.createWithTransport()
            if (transportPtr == 0L || transportPtr != clientPtr) {
                Log.e(TAG, "start: createWithTransport failed (returned=$transportPtr, expected=$clientPtr)")
                manager.unregisterReceiver()
                return false
            }

            EapClientJni.setHostOwned(true)

            usbManager = manager
            isStarted = true
            Log.d(TAG, "start: transport running (host-owned), clientPtr=$clientPtr")
            return true
        }
    }
}
