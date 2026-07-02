#if os(iOS)
import ExternalAccessory
import Foundation

/// iPadOS transport over the MFi ExternalAccessory framework, feeding the
/// skylelib client in **push mode**.
///
/// - Discovers the Skyle accessory by its MFi protocol string.
/// - Reads bytes off the input stream and pushes them into the C client via
///   `eap_client_process_received_data`.
/// - The C library's send thread calls `write(_:length:)` (registered as the
///   push-transport write callback), which queues bytes onto the output stream.
final class ExternalAccessoryTransport: NSObject, StreamDelegate {
    /// MFi protocol string — must match the app's
    /// `UISupportedExternalAccessoryProtocols` Info.plist entry.
    static let protocolString = "de.eyev.eap"

    private let client: OpaquePointer
    private var session: EASession?
    private var accessory: EAAccessory?

    // Output backpressure: write on a background queue, gated by space-available.
    private let writeQueue = DispatchQueue(label: "de.eyev.skyle.write")
    private let spaceAvailable = DispatchSemaphore(value: 0)
    private var pending = [Data]()
    private let pendingLock = NSLock()

    init(client: OpaquePointer) {
        self.client = client
        super.init()
    }

    func start() {
        let manager = EAAccessoryManager.shared()
        manager.registerForLocalNotifications()
        NotificationCenter.default.addObserver(
            self, selector: #selector(accessoryConnected),
            name: .EAAccessoryDidConnect, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(accessoryDisconnected),
            name: .EAAccessoryDidDisconnect, object: nil)
        connectToConnectedAccessory()
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        closeSession()
        EAAccessoryManager.shared().unregisterForLocalNotifications()
    }

    // MARK: - Write callback (called by the C send thread)

    /// Returns the number of bytes accepted, or a negative error code.
    func write(_ data: UnsafePointer<UInt8>?, length: UInt16) -> Int32 {
        guard let data = data, length > 0 else { return 0 }
        let chunk = Data(bytes: data, count: Int(length))
        pendingLock.lock(); pending.append(chunk); pendingLock.unlock()
        drain()
        return Int32(length)
    }

    private func drain() {
        writeQueue.async { [weak self] in
            guard let self = self else { return }
            while true {
                self.pendingLock.lock()
                let next = self.pending.isEmpty ? nil : self.pending.removeFirst()
                self.pendingLock.unlock()
                guard let chunk = next, let out = self.session?.outputStream else { return }

                self.spaceAvailable.wait()
                chunk.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                    guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
                    var written = 0
                    while written < chunk.count {
                        let n = out.write(base + written, maxLength: chunk.count - written)
                        if n <= 0 { return }
                        written += n
                    }
                }
            }
        }
    }

    // MARK: - Accessory discovery / session

    @objc private func accessoryConnected(_ note: Notification) { connectToConnectedAccessory() }
    @objc private func accessoryDisconnected(_ note: Notification) { closeSession() }

    private func connectToConnectedAccessory() {
        guard session == nil else { return }
        let match = EAAccessoryManager.shared().connectedAccessories.first {
            $0.protocolStrings.contains(Self.protocolString)
        }
        guard let accessory = match else { return }
        openSession(for: accessory)
    }

    private func openSession(for accessory: EAAccessory) {
        guard let session = EASession(accessory: accessory, forProtocol: Self.protocolString) else { return }
        self.accessory = accessory
        self.session = session

        if let input = session.inputStream {
            input.delegate = self
            input.schedule(in: .main, forMode: .default)
            input.open()
        }
        if let output = session.outputStream {
            output.delegate = self
            output.schedule(in: .main, forMode: .default)
            output.open()
        }
    }

    private func closeSession() {
        if let input = session?.inputStream {
            input.close(); input.remove(from: .main, forMode: .default)
        }
        if let output = session?.outputStream {
            output.close(); output.remove(from: .main, forMode: .default)
        }
        session = nil
        accessory = nil
    }

    // MARK: - StreamDelegate

    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .hasBytesAvailable:
            if let input = aStream as? InputStream { readAvailable(from: input) }
        case .hasSpaceAvailable:
            if (aStream as? OutputStream) === session?.outputStream { spaceAvailable.signal() }
        default:
            break
        }
    }

    private func readAvailable(from input: InputStream) {
        let capacity = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { buffer.deallocate() }
        while input.hasBytesAvailable {
            let n = input.read(buffer, maxLength: capacity)
            if n > 0 {
                // Feed each chunk into the push-mode parser.
                eap_client_process_received_data(client, buffer, UInt16(n))
            } else {
                break
            }
        }
    }
}
#endif
