package de.eyev.flutter_eap

import io.flutter.Log

/**
 * JNI bridge to the native flutter_eap C library
 *
 * This allows Kotlin to call C functions directly without going through Dart.
 * Used for high-performance USB data feeding and packet retrieval.
 */
object EapClientJni {
    /**
     * Get the singleton EAP client instance
     * Returns the same client instance regardless of initialization order
     * 
     * @return Client pointer, or 0 on error
     */
    external fun getInstance(): Long

    /**
     * Configure transport on the singleton EAP client
     * Called from Kotlin to set up USB transport layer
     * Can be called before or after Dart sets callbacks
     * 
     * @return Client pointer, or 0 on error
     */
    external fun createWithTransport(): Long


    init {
        try {
            System.loadLibrary("flutter_eap")
            Log.d("EapClientJni", "Loaded libflutter_eap.so")
        } catch (e: UnsatisfiedLinkError) {
            Log.e("EapClientJni", "Failed to load libflutter_eap.so", e)
            throw e
        }
    }

    /**
     * Set USB transport callbacks
     * The C library will call read() and write() methods from its background thread
     *
     * @param clientPtr Native pointer to eap_client
     * @param callback Object implementing UsbTransportCallback interface
     */
    external fun setUsbWriteCallback(clientPtr: Long, callback: UsbTransportCallback)

    /**
     * Get current connection state
     *
     * @param clientPtr Native pointer to eap_client
     * @return State value (see eap_connection_state enum)
     */
    external fun getState(clientPtr: Long): Int

    /**
     * Clear Dart callbacks on the bridge context.
     * Call this before the Flutter engine tears down to ensure the C background
     * thread cannot invoke a closed NativeCallable.
     *
     * @param clientPtr Native pointer to eap_client
     */
    external fun clearCallbacks(clientPtr: Long)

    /**
     * Mark the transport as owned by the Kotlin host (accessibility service).
     * While owned, Dart-initiated destroy/disconnect are no-ops and connect
     * only acts from the DISCONNECTED state - no Flutter engine teardown can
     * disrupt the shared link.
     */
    external fun setHostOwned(owned: Boolean)

    /**
     * Remove one engine's callback subscriber (fan-out slot). Called from
     * onDetachedFromEngine with the handle the engine's Dart side reported.
     * Safe with stale or unknown handles (no-op).
     *
     * @param clientPtr Native pointer to eap_client
     * @param handle Subscriber handle returned by flutter_eap_add_callbacks
     */
    external fun removeSubscriber(clientPtr: Long, handle: Long)

    // =========================================================================
    // Skyle Link (multi-app sharing via the automatic transport supervisor)
    // =========================================================================

    /**
     * Set the Skyle Link identity: HELLO app id, priority tier (0 = skylex,
     * 1 = partner, 2 = default), and whether this app currently holds the
     * platform USB permission for the tracker. Safe to call repeatedly -
     * re-push whenever the permission state changes; the supervisor reacts
     * on its next evaluation.
     */
    external fun setIdentity(appId: String, tier: Int, usbCapable: Boolean)

    /**
     * Enable/disable the automatic transport supervisor. Enabling returns
     * immediately (the OWNER/CLIENT decision lands on the supervisor thread).
     * Disabling is a deliberate stop: OWNER sends BYE(handover) to all hub
     * clients and releases USB via the ownership listener, CLIENT closes;
     * no re-election happens until re-enabled.
     */
    external fun setSupervisorEnabled(enabled: Boolean)

    /**
     * Register the USB ownership listener. The supervisor grants ownership
     * (wanted=true: open/claim the USB device) and releases it (wanted=false:
     * close/release) through it. Fired on native supervisor threads - hop to
     * a handler for the USB work and never block. Passing null clears the
     * listener and the native callback slot.
     */
    external fun setUsbOwnershipListener(listener: UsbOwnershipListener?)

    /**
     * Disconnect the client and stop its background thread. Only effective
     * after setHostOwned(false) - while host-owned the native bridge
     * suppresses disconnects. Used by EapUsbHost.stop().
     *
     * @param clientPtr Native pointer to eap_client
     */
    external fun disconnect(clientPtr: Long): Int
}

/**
 * Skyle Link supervisor USB ownership grants. wanted=true: open/claim the
 * USB device and keep feeding the registered transport; wanted=false: close
 * the device and release the interface claim (handover/preempt/disable).
 * Fired on native supervisor threads - implementations must hop to a handler
 * for the USB work and never block the caller.
 */
interface UsbOwnershipListener {
    fun onUsbOwnershipChanged(wanted: Boolean)
}

/**
 * Callback interface for USB transport (read and write)
 * The C library calls these methods directly from its background thread
 */
interface UsbTransportCallback {
    /**
     * Read data from USB device
     * @param buffer Buffer to fill with data
     * @param timeout Timeout in milliseconds
     * @return Number of bytes read, 0 on timeout, or negative value on error
     */
    fun read(buffer: ByteArray, timeout: Int): Int

    /**
     * Write data to USB device
     * @param data Bytes to write
     * @return Number of bytes written, or negative value on error
     */
    fun write(data: ByteArray): Int

    /**
     * Check if USB device is still connected
     * @return true if device is connected, false otherwise
     */
    fun isDeviceConnected(): Boolean
}
