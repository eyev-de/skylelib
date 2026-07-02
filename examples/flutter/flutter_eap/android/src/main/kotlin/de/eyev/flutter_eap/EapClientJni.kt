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
