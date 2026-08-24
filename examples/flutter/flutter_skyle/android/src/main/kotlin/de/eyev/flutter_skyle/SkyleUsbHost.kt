package de.eyev.flutter_skyle

import android.content.Context
import io.flutter.Log

/**
 * Process-wide owner of the Skyle USB transport, independent of any Flutter
 * engine.
 *
 * Started by the accessibility service (via the app's service-ready hook) so
 * the eye-tracker link exists before - and survives independent of - every
 * Flutter engine. FlutterSkylePlugin.onAttachedToEngine calls start() as an
 * idempotent fallback for setups without the service (first run before the
 * accessibility permission is granted, plain plugin consumers), gated by the
 * de.eyev.flutter_skyle.AUTO_START_USB_HOST manifest meta-data (default true).
 *
 * Once started, setHostOwned(true) makes Dart-initiated destroy/disconnect
 * no-ops in the native bridge. In normal operation the transport lives as
 * long as the process; stop() exists for the orderly quit path only (the app
 * hands the tracker over and shuts eye control down).
 *
 * Skyle Link: transport selection is fully automatic (spec section 10).
 * start() registers the transport plumbing, publishes the app's identity
 * (skylex/tier 0 for the Skyle X package, manifest meta-data otherwise),
 * wires the supervisor's USB ownership grants to [UsbEndpointManager], and
 * enables the supervisor. The supervisor then serves the hub / claims USB /
 * dials another hub / handles preemption entirely on its own - including
 * live mid-session handovers. Supervisor failures never break transport
 * bring-up (an old libflutter_skyle.so degrades to plain USB).
 */
object SkyleUsbHost {
    private const val TAG = "SkyleUsbHost"

    // Tier 0 (skylex, always converges to USB ownership) is reserved for the
    // Skyle X app itself. Every other host-owning consumer (example app,
    // integrations that keep AUTO_START_USB_HOST=true) gets its identity from
    // the same manifest meta-data as the pure-client path in
    // FlutterSkylePlugin: APP_ID (default packageName) and PRIORITY_TIER
    // (default 2, clamped to 1..2 - meta-data cannot claim tier 0).
    private const val SKYLEX_PACKAGE = "de.eyev.skylex"
    private const val META_APP_ID = "de.eyev.flutter_skyle.APP_ID"
    private const val META_PRIORITY_TIER = "de.eyev.flutter_skyle.PRIORITY_TIER"

    private val lock = Any()

    // Resolved once in start() (identity re-pushes must match it exactly).
    private var appId: String = ""
    private var tier: Int = 2

    private fun resolveIdentity(context: Context) {
        if (context.packageName == SKYLEX_PACKAGE) {
            appId = "skylex"
            tier = 0
            return
        }
        appId = context.packageName
        tier = 2
        try {
            val meta = context.packageManager.getApplicationInfo(context.packageName, android.content.pm.PackageManager.GET_META_DATA).metaData
            meta?.getString(META_APP_ID)?.takeIf { it.isNotBlank() }?.let { appId = it }
            tier = (meta?.getInt(META_PRIORITY_TIER, 2) ?: 2).coerceIn(1, 2)
        } catch (e: Exception) {
            Log.w(TAG, "resolveIdentity: meta-data read failed, using defaults: $e")
        }
    }

    @Volatile
    var isStarted: Boolean = false
        private set

    // Kept alive while started; the native bridge holds a JNI global ref to it
    // as the transport callback.
    private var usbManager: UsbEndpointManager? = null

    // Supervisor USB ownership grants, fired on native supervisor threads.
    // setOwnershipWanted hops onto the main looper before touching USB.
    private val usbOwnershipListener = object : UsbOwnershipListener {
        override fun onUsbOwnershipChanged(wanted: Boolean) {
            Log.d(TAG, "supervisor USB ownership -> $wanted")
            usbManager?.setOwnershipWanted(wanted)
        }
    }

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
            resolveIdentity(appContext)

            val clientPtr = SkyleClientJni.getInstance()
            if (clientPtr == 0L) {
                Log.e(TAG, "start: failed to get native client instance")
                return false
            }

            // The old onUsbConnected/onUsbDisconnected/onUsbSessionOpened
            // method-channel notifications had no Dart listener - log only.
            // onUsbCapableChanged re-pushes the identity so the supervisor
            // re-evaluates election eligibility when the permission state
            // changes (manifest grant landed, dialog answered, device gone).
            val manager = UsbEndpointManager(
                appContext,
                onDeviceConnected = { device -> Log.d(TAG, "USB device connected: ${device.deviceName}") },
                onDeviceDisconnected = { device -> Log.d(TAG, "USB device disconnected: ${device.deviceName}") },
                onOpenedSession = { Log.d(TAG, "USB session opened") },
                onUsbCapableChanged = { capable ->
                    Log.d(TAG, "usb_capable -> $capable")
                    try {
                        SkyleClientJni.setIdentity(appId, tier, capable)
                    } catch (e: Throwable) {
                        Log.e(TAG, "identity re-push failed: $e")
                    }
                },
            )

            // Order is load-bearing: the JNI transport callback must be
            // registered BEFORE createWithTransport starts the C threads,
            // or the background thread could read/write with no callback.
            SkyleClientJni.setUsbWriteCallback(clientPtr, manager)
            manager.registerReceiver()

            val transportPtr = SkyleClientJni.createWithTransport()
            if (transportPtr == 0L || transportPtr != clientPtr) {
                Log.e(TAG, "start: createWithTransport failed (returned=$transportPtr, expected=$clientPtr)")
                manager.unregisterReceiver()
                return false
            }

            SkyleClientJni.setHostOwned(true)

            usbManager = manager
            isStarted = true
            Log.d(TAG, "start: transport running (host-owned), clientPtr=$clientPtr")

            // Skyle Link supervisor: best-effort, transport bring-up never
            // depends on it. Order is load-bearing: identity and the
            // ownership listener must be in place BEFORE the supervisor is
            // enabled, or the first OWNER grant could be missed.
            try {
                SkyleClientJni.setIdentity(appId, tier, manager.hasUsbPermission())
                SkyleClientJni.setUsbOwnershipListener(usbOwnershipListener)
                SkyleClientJni.setSupervisorEnabled(true)
                Log.d(TAG, "start: Skyle Link supervisor enabled (appId=$appId, tier=$tier, usbCapable=${manager.hasUsbPermission()})")
            } catch (e: Throwable) {
                // UnsatisfiedLinkError with an old libflutter_skyle.so, or
                // anything unexpected: eye tracking must keep working. With
                // no supervisor nothing grants USB ownership, so open the
                // device directly as a fallback.
                Log.e(TAG, "start: Skyle Link supervisor bring-up failed: $e - opening USB directly")
                manager.setOwnershipWanted(true)
            }
            return true
        }
    }

    /**
     * Best-effort orderly quit/handover: disable the supervisor (a deliberate
     * stop - as OWNER it sends BYE(handover) to all hub clients, frees the
     * port, and releases USB ownership through the listener), clear native
     * host ownership, stop the client's background threads, and close the USB
     * device directly (bounded belt-and-suspenders for the async ownership
     * release; closing the UsbDeviceConnection releases the claimed interface
     * so another process can claim it). Idempotent; synchronized with start().
     *
     * Known limitation: the native transport callbacks (read/write/
     * isDeviceConnected) stay registered as a JNI global ref until the next
     * start() re-registers them - after stop() they report "disconnected" and
     * fail I/O, which is safe but not a full unbind. Dropping the ref without
     * a re-registration would require a dedicated native call that does not
     * exist today.
     */
    @JvmStatic
    fun stop() {
        synchronized(lock) {
            if (!isStarted) {
                return
            }
            Log.d(TAG, "stop: releasing Skyle Link supervisor + USB transport")

            try {
                // Non-blocking deliberate stop; the BYE/teardown runs on the
                // supervisor thread and its ownership(false) closes USB via
                // the listener. No re-election until the next start().
                SkyleClientJni.setSupervisorEnabled(false)
            } catch (e: Throwable) {
                Log.e(TAG, "stop: supervisor shutdown failed: $e")
            }

            // Clear host ownership FIRST: the native bridge suppresses
            // disconnects while host-owned.
            SkyleClientJni.setHostOwned(false)

            val clientPtr = SkyleClientJni.getInstance()
            if (clientPtr != 0L) {
                val result = SkyleClientJni.disconnect(clientPtr)
                Log.d(TAG, "stop: native disconnect -> $result")
            }

            usbManager?.let { manager ->
                manager.disconnect()
                manager.unregisterReceiver()
            }
            usbManager = null

            try {
                SkyleClientJni.setUsbOwnershipListener(null)
            } catch (e: Throwable) {
                Log.e(TAG, "stop: ownership listener clear failed: $e")
            }

            isStarted = false
            Log.d(TAG, "stop: transport released")
        }
    }
}
