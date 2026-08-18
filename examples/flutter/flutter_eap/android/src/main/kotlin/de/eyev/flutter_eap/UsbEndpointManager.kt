package de.eyev.flutter_eap

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.*
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.Log


class UsbEndpointManager(
    private val context: Context,
    private val onDeviceConnected: (UsbDevice) -> Unit,
    private val onDeviceDisconnected: (UsbDevice) -> Unit,
    private val onOpenedSession: () -> Unit
) : UsbTransportCallback {
    private val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
    private val connectionLock = Any()

    // Per-direction transfer locks. IN and OUT are independent USB pipes, so a
    // write blocked on its timeout must never delay reads: when reads stall, the
    // device's writer queue backs up and the device declares the client inactive
    // (heartbeat timeout -> soft reset). closeDevice() acquires BOTH transfer
    // locks before closing the native connection, so an in-flight bulkTransfer
    // can never dereference a freed libusbhost context (SIGSEGV).
    // Lock order when nesting: readLock -> writeLock -> connectionLock.
    private val readLock = Any()
    private val writeLock = Any()

    private var connectedDevice: UsbDevice? = null
    private var connection: UsbDeviceConnection? = null
    private var endpointIn: UsbEndpoint? = null
    private var endpointOut: UsbEndpoint? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private val targetVendorId = 0x3729
    private val targetProductId = 0x7333

    companion object {
        // A healthy device drains the OUT endpoint in single-digit milliseconds.
        // Keep this short so a stalled device fails writes fast: the C send
        // thread counts consecutive write failures and forces a reconnect,
        // instead of blocked writes stalling the link for 100ms apiece.
        private const val WRITE_TIMEOUT_MS = 20

        // Manifest-grant poll: 100ms steps. 5s covers slow boots where the
        // UsbAttachActivity route needs longer before falling back to an
        // explicit permission dialog.
        private const val GRANT_POLL_INTERVAL_MS = 100L
        private const val GRANT_POLL_MAX_ATTEMPTS = 50

        // Open retries: a failed openDevice/claimInterface right after attach
        // is usually transient (enumeration still settling, stale connection
        // to a re-enumerated instance not torn down yet). The open path is the
        // ONLY way the link comes up - the native transport callbacks are
        // read/write/isDeviceConnected only, so the C reconnect loop cannot
        // re-trigger it. Without retries a single failure kept the link down
        // until a physical replug.
        private const val OPEN_RETRY_MAX_ATTEMPTS = 15
        private const val OPEN_RETRY_BASE_DELAY_MS = 500L
        private const val OPEN_RETRY_MAX_DELAY_MS = 5000L
    }

    private val isConnected: Boolean
        get() = synchronized(connectionLock) {
            connection != null && connectedDevice != null && endpointIn != null && endpointOut != null
        }

    private var requestingPermission: Boolean = false

    // Cancels pending open retries: bumped when a detach invalidates the chain.
    // Retry closures capture the generation at schedule time and bail when it
    // moved on.
    private var openRetryGeneration = 0

    private val ACTION_USB_PERMISSION = "${context.packageName}.USB_PERMISSION"
    private val USB_PERMISSION_REQUEST_CODE = 0

    private fun findTargetDevice(): UsbDevice? =
        usbManager.deviceList.values.firstOrNull { it.vendorId == targetVendorId && it.productId == targetProductId }

    /** True when the open connection belongs to exactly this device instance. */
    private fun isConnectedTo(device: UsbDevice): Boolean = synchronized(connectionLock) {
        isConnected && connectedDevice?.deviceName == device.deviceName
    }

    // Poll hasPermission() while the manifest-routed UsbAttachActivity grant is
    // propagating. When USB_DEVICE_ATTACHED fires, Android routes the intent to
    // UsbAttachActivity and grants our package USB permission - but that grant
    // lands a few hundred ms after the runtime broadcast does. Calling
    // requestPermission() in that window races the manifest path, pops a second
    // (non-persistent) dialog on top of the system one, and corrupts the
    // requestingPermission flag. Polling lets the manifest grant arrive first.
    private fun pollForManifestGrantAndOpen(device: UsbDevice, attempt: Int = 0) {
        // Compare against THIS device instance: a lingering connection to a
        // previous enumeration of the tracker (device re-enumerated after a
        // firmware reset, DETACHED not processed yet) must not abort the chain
        // for the new instance - openDevice tears the stale one down.
        if (isConnectedTo(device)) return
        if (usbManager.deviceList.values.none { it.deviceName == device.deviceName }) {
            Log.d("UsbEndpointManager", "Device ${device.deviceName} gone - stopping grant poll (attach broadcast restarts it)")
            return
        }
        if (usbManager.hasPermission(device)) {
            Log.d("UsbEndpointManager", "Manifest grant landed after $attempt attempt(s), opening device")
            if (!openDevice(device)) scheduleOpenRetry(attempt = 0)
            return
        }
        if (attempt >= GRANT_POLL_MAX_ATTEMPTS) {
            // Manifest route clearly did not happen (e.g. device was already
            // plugged in at app startup on a fresh install, before any user
            // has checked "Use by default"). Fall back to an explicit
            // permission request so the user is at least prompted.
            Log.d("UsbEndpointManager", "Manifest grant never arrived, falling back to requestPermission()")
            requestPermissionAndOpen(device)
            return
        }
        mainHandler.postDelayed({ pollForManifestGrantAndOpen(device, attempt + 1) }, GRANT_POLL_INTERVAL_MS)
    }

    private fun requestPermissionAndOpen(device: UsbDevice) {
        Log.d("UsbEndpointManager", "requestPermissionAndOpen called - requestingPermission=$requestingPermission, isConnected=$isConnected")

        if (requestingPermission || isConnectedTo(device)) {
            Log.d("UsbEndpointManager", "Already requesting permission or connected, ignoring request")
            return
        }
        requestingPermission = true

        // Check if permission is already granted
        if (usbManager.hasPermission(device)) {
            Log.d("UsbEndpointManager", "Permission already granted, opening device directly")
            requestingPermission = false
            if (!openDevice(device)) scheduleOpenRetry(attempt = 0)
            return
        }

        Log.d("UsbEndpointManager", "Requesting permission for device")
        // The intent must stay mutable so the system can attach EXTRA_DEVICE /
        // EXTRA_PERMISSION_GRANTED. Below S mutability is the default and
        // FLAG_MUTABLE does not exist yet.
        val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val permissionIntent = PendingIntent.getBroadcast(
            context,
            USB_PERMISSION_REQUEST_CODE,
            Intent(ACTION_USB_PERMISSION).apply {
                setPackage(context.packageName)
            },
            pendingIntentFlags
        )
        try {
            usbManager.requestPermission(device, permissionIntent)
        } catch (e: Exception) {
            // Stale device object (unplugged mid-flow): reset so the next
            // attach can request again.
            Log.w("UsbEndpointManager", "requestPermission failed: ${e.message}")
            requestingPermission = false
        }
    }

    /**
     * Retry the open path with backoff. Re-resolves the current device
     * instance each attempt (the triggering object may be stale after a
     * re-enumeration) and re-enters the grant flow when permission is missing.
     */
    private fun scheduleOpenRetry(attempt: Int) {
        if (attempt >= OPEN_RETRY_MAX_ATTEMPTS) {
            Log.e("UsbEndpointManager", "Giving up opening device after $attempt retries - replug required")
            return
        }
        val generation = openRetryGeneration
        val delay = minOf(OPEN_RETRY_BASE_DELAY_MS * (attempt + 1), OPEN_RETRY_MAX_DELAY_MS)
        Log.d("UsbEndpointManager", "Retrying open in ${delay}ms (attempt ${attempt + 1}/$OPEN_RETRY_MAX_ATTEMPTS)")
        mainHandler.postDelayed({
            if (generation != openRetryGeneration) return@postDelayed
            val current = findTargetDevice()
            if (current == null) {
                Log.d("UsbEndpointManager", "Target device gone - stopping open retries (attach broadcast restarts them)")
                return@postDelayed
            }
            if (isConnectedTo(current)) return@postDelayed
            if (usbManager.hasPermission(current)) {
                if (!openDevice(current)) scheduleOpenRetry(attempt + 1)
            } else {
                pollForManifestGrantAndOpen(current)
            }
        }, delay)
    }

    // Typed getParcelableExtra needs API 33; the untyped one is deprecated there.
    private fun usbDeviceExtra(intent: Intent): UsbDevice? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
        }

    private val usbReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            Log.d("UsbEndpointManager", "Received intent: ${intent?.action}")

            when (intent?.action) {
                UsbManager.ACTION_USB_DEVICE_ATTACHED -> {
                    val device = usbDeviceExtra(intent)
                    device?.let {
                        Log.d("UsbEndpointManager", "Attached: ${it.deviceName}, vendorId=${it.vendorId}, productId=${it.productId}")
                        // logUsbDevice(it)
                        if (it.vendorId == targetVendorId && it.productId == targetProductId) {
                            pollForManifestGrantAndOpen(device)
                        }
                    }
                }
                UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                    val device = usbDeviceExtra(intent)
                    device?.let {
                        Log.d("UsbEndpointManager", "Detached: ${it.deviceName}, vendorId=${it.vendorId}, productId=${it.productId}")
                        // logUsbDevice(it)
                        if (it.vendorId == targetVendorId && it.productId == targetProductId) {
                            Log.d("UsbEndpointManager", "Target device detached, closing connection and resetting state")
                            requestingPermission = false
                            openRetryGeneration++
                            closeDevice()
                        }
                    }
                }
                ACTION_USB_PERMISSION -> {
                    synchronized(this) {
                        Log.d("UsbEndpointManager", "=== PERMISSION RESPONSE RECEIVED ===")
                        var device = usbDeviceExtra(intent)
                        val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)

                        Log.d("UsbEndpointManager", "Permission response - device: ${device?.deviceName}, granted: $granted")

                        if (granted && device != null) {
                            Log.d("UsbEndpointManager", "USB permission granted, opening device")
                            if (!openDevice(device)) scheduleOpenRetry(attempt = 0)
                        } else {
                            if (device == null) {
                                Log.w("UsbEndpointManager", "USB permission response received but device is null (even with fallback)")
                            } else {
                                Log.w("UsbEndpointManager", "USB permission denied by user")
                            }
                        }
                        // Always reset flag after permission response
                        requestingPermission = false
                    }
                }
            }
        }
    }


    fun registerReceiver() {
        val usbConnectionFilter = IntentFilter()
        usbConnectionFilter.addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
        usbConnectionFilter.addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        usbConnectionFilter.addAction(ACTION_USB_PERMISSION)

        // RECEIVER_NOT_EXPORTED is mandatory for runtime receivers with custom
        // actions from targetSdk 34 on; the flagged overload needs API 33. The
        // system USB broadcasts and the own-package permission broadcast are
        // still delivered to a non-exported receiver.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(usbReceiver, usbConnectionFilter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(usbReceiver, usbConnectionFilter)
        }

        val deviceList: HashMap<String, UsbDevice> = usbManager.deviceList
        deviceList.values.forEach {
            if (it.vendorId == targetVendorId && it.productId == targetProductId) {
                // Device already plugged in at startup. If the user previously checked
                // "Use by default", hasPermission() is already true and openDevice runs
                // immediately. Otherwise the poller falls back to requestPermission().
                pollForManifestGrantAndOpen(it)
            }
        }
    }

    fun unregisterReceiver() {
        try {
            context.unregisterReceiver(usbReceiver)
        } catch (e: IllegalArgumentException) {
            // Receiver was not registered
            Log.w("UsbEndpointManager", "Receiver was not registered: ${e.message}")
        }
    }

    fun connect(): Boolean {
        Log.d("UsbEndpointManager", "connect() called - isConnected=$isConnected, requestingPermission=$requestingPermission")

        // If already connected, return true
        val device: UsbDevice?
        synchronized(connectionLock) {
            if (isConnected) {
                device = connectedDevice
            } else {
                device = null
            }
        }

        if (device != null) {
            Log.d("UsbEndpointManager", "Already connected, notifying callback")
            onDeviceConnected(device)
            return true
        }

        // Scan for target device
        val deviceList: HashMap<String, UsbDevice> = usbManager.deviceList

        for (targetDevice in deviceList.values) {
            if (targetDevice.vendorId == targetVendorId && targetDevice.productId == targetProductId) {
                Log.d("UsbEndpointManager", "Found target device: ${targetDevice.deviceName}")
                requestPermissionAndOpen(targetDevice)
                return true
            }
        }

        // No target device found
        Log.d("UsbEndpointManager", "No target device found for connection")
        return false
    }

    fun disconnect() {
        closeDevice()
    }

    /** Returns true when the device (or the same instance, via a racing caller) ends up open. */
    private fun openDevice(device: UsbDevice): Boolean {
        Log.d("UsbEndpointManager", "openDevice called - requestingPermission=$requestingPermission, isConnected=$isConnected")

        // A lingering connection to a PREVIOUS enumeration of the tracker
        // (firmware reset re-enumerates faster than the DETACHED broadcast is
        // processed) blocks the open below - tear it down first. Must happen
        // outside connectionLock: closeDevice takes the transfer locks first
        // (lock order readLock -> writeLock -> connectionLock).
        val staleName = synchronized(connectionLock) {
            val current = connectedDevice
            if (connection != null && current != null && current.deviceName != device.deviceName) current.deviceName else null
        }
        if (staleName != null) {
            Log.d("UsbEndpointManager", "Closing stale connection to $staleName before opening ${device.deviceName}")
            closeDevice()
        }

        try {
            synchronized(connectionLock) {
                // Guard against racing callers (e.g. initial scan + attach broadcast +
                // multiple plugin instances) all trying to open the same device. The
                // first one through wins; later callers see a live connection and bail.
                if (connection != null) {
                    Log.d("UsbEndpointManager", "openDevice: already have an open connection, skipping")
                    return true
                }
                connection = usbManager.openDevice(device)
                if (connection == null) {
                    Log.e("UsbEndpointManager", "Failed to open USB device connection")
                    requestingPermission = false
                    return false
                }
                connectedDevice = device

                // 0 is HID
                // 1 is iAP / USB raw
                val usbInterface = device.getInterface(1)
                val claimResult = connection?.claimInterface(usbInterface, true)
                if (claimResult != true) {
                    Log.e("UsbEndpointManager", "Failed to claim USB interface 1 (result=$claimResult)")
                    connection?.close()
                    connection = null
                    connectedDevice = null
                    requestingPermission = false
                    return false
                }

                for (i in 0 until usbInterface.endpointCount) {
                    val ep = usbInterface.getEndpoint(i)
                    if (ep.direction == UsbConstants.USB_DIR_IN) {
                        endpointIn = ep
                        Log.d("UsbEndpointManager", "Found IN endpoint: address=0x${ep.address.toString(16)}, maxPacketSize=${ep.maxPacketSize}")
                    }
                    if (ep.direction == UsbConstants.USB_DIR_OUT) {
                        endpointOut = ep
                        Log.d("UsbEndpointManager", "Found OUT endpoint: address=0x${ep.address.toString(16)}, maxPacketSize=${ep.maxPacketSize}")
                    }
                }

                if (endpointIn == null || endpointOut == null) {
                    Log.e("UsbEndpointManager", "Failed to find required endpoints (IN=${endpointIn != null}, OUT=${endpointOut != null})")
                    connection?.releaseInterface(usbInterface)
                    connection?.close()
                    connection = null
                    endpointIn = null
                    endpointOut = null
                    connectedDevice = null
                    requestingPermission = false
                    return false
                }

                Log.d("UsbEndpointManager", "Successfully opened device: ${device.deviceName}, vendorId=${device.vendorId}, productId=${device.productId}")
                requestingPermission = false
            }

            // Call callbacks outside of lock to avoid potential deadlocks
            mainHandler.post {
                onDeviceConnected(device)
                onOpenedSession()
            }
            return true
        } catch (e: Exception) {
            Log.e("UsbEndpointManager", "Exception in openDevice: ${e.message}", e)
            synchronized(readLock) {
                synchronized(writeLock) {
                    synchronized(connectionLock) {
                        closeDeviceInternal()
                        requestingPermission = false
                    }
                }
            }
            return false
        }
    }

    private fun closeDevice() {
        Log.d("UsbEndpointManager", "closeDevice called - isConnected=$isConnected")

        val device: UsbDevice?
        // Take both transfer locks (readLock -> writeLock -> connectionLock) so no
        // bulkTransfer is in flight when the native connection is closed.
        // Worst-case wait: one read timeout (5ms) + one write timeout (20ms).
        synchronized(readLock) {
            synchronized(writeLock) {
                synchronized(connectionLock) {
                    if (!isConnected) return

                    device = connectedDevice
                    closeDeviceInternal()
                }
            }
        }

        // Call callback outside of lock to avoid potential deadlocks
        device?.let { mainHandler.post { onDeviceDisconnected(it) } }

        Log.d("UsbEndpointManager", "closeDevice completed - all state reset")
    }

    private fun closeDeviceInternal() {
        // Must be called with readLock, writeLock and connectionLock held
        // (see closeDevice) so no bulkTransfer can be using the connection.
        try {
            connection?.close()
        } catch (e: Exception) {
            Log.w("UsbEndpointManager", "Error closing connection: ${e.message}")
        }

        // Reset all connection state
        connection = null
        endpointIn = null
        endpointOut = null
        connectedDevice = null
    }

    override fun read(buffer: ByteArray, timeout: Int): Int {
        if (buffer.isEmpty()) return 0

        // Hold readLock for the entire bulkTransfer so closeDevice() (which takes
        // both transfer locks before closing) can never free the native connection
        // under an in-flight transfer. The connection/endpoint snapshot is taken
        // under connectionLock, but the transfer itself deliberately does NOT hold
        // connectionLock: writes run concurrently under their own writeLock.
        synchronized(readLock) {
            val ep: UsbEndpoint
            val conn: UsbDeviceConnection
            synchronized(connectionLock) {
                if (!isConnected) return -1
                ep = endpointIn ?: return -1
                conn = connection ?: return -1
            }

            return try {
                val len = conn.bulkTransfer(ep, buffer, buffer.size, timeout)
                // Android bulkTransfer returns -1 for both timeouts and actual errors.
                // We cannot distinguish them here, so return 0 (timeout) when still connected.
                // Dead links are detected by the C library via consecutive send-thread
                // write failures and the RX-staleness timeout.
                when {
                    len > 0 -> len
                    len == 0 -> 0
                    else -> if (isConnected) 0 else -1
                }
            } catch (e: Exception) {
                Log.e("UsbEndpointManager", "read() exception: ${e.message}", e)
                -1
            }
        }
    }

    override fun write(data: ByteArray): Int {
        if (data.isEmpty()) return 0

        // See read() for the locking scheme. Writes hold only writeLock during
        // the transfer so a write blocked on its timeout never starves reads.
        synchronized(writeLock) {
            val ep: UsbEndpoint
            val conn: UsbDeviceConnection
            synchronized(connectionLock) {
                if (!isConnected) return -1
                ep = endpointOut ?: return -1
                conn = connection ?: return -1
            }

            return try {
                conn.bulkTransfer(ep, data, data.size, WRITE_TIMEOUT_MS)
            } catch (e: Exception) {
                Log.e("UsbEndpointManager", "write() exception: ${e.message}", e)
                -1
            }
        }
    }

    override fun isDeviceConnected(): Boolean {
        return isConnected
    }

    fun logUsbDevice(device: UsbDevice) {
        Log.d("UsbEndpointManager", "------ USB Device Info ------")
        Log.d("UsbEndpointManager", "Device Name: ${device.deviceName}")
        Log.d("UsbEndpointManager", "Vendor ID: ${device.vendorId}")
        Log.d("UsbEndpointManager", "Product ID: ${device.productId}")
        Log.d("UsbEndpointManager", "Device ID: ${device.deviceId}")
        Log.d("UsbEndpointManager", "Device Class: ${device.deviceClass}")
        Log.d("UsbEndpointManager", "Device Subclass: ${device.deviceSubclass}")
        Log.d("UsbEndpointManager", "Device Protocol: ${device.deviceProtocol}")
        Log.d("UsbEndpointManager", "Manufacturer Name: ${device.manufacturerName}")
        Log.d("UsbEndpointManager", "Product Name: ${device.productName}")
        Log.d("UsbEndpointManager", "Serial Number: ${device.serialNumber}")
        Log.d("UsbEndpointManager", "Configuration Count: ${device.configurationCount}")
        Log.d("UsbEndpointManager", "Interface Count: ${device.interfaceCount}")
        for (i in 0 until device.interfaceCount) {
            val intf = device.getInterface(i)
            Log.d("UsbEndpointManager", "  Interface $i: class=${intf.interfaceClass}, subclass=${intf.interfaceSubclass}, protocol=${intf.interfaceProtocol}, endpointCount=${intf.endpointCount}")
            for (j in 0 until intf.endpointCount) {
                val ep = intf.getEndpoint(j)
                Log.d("UsbEndpointManager", "    Endpoint $j: address=${ep.address}, attributes=${ep.attributes}, direction=${ep.direction}, type=${ep.type}, maxPacketSize=${ep.maxPacketSize}")
            }
        }
        Log.d("UsbEndpointManager", "-----------------------------")
    }
}