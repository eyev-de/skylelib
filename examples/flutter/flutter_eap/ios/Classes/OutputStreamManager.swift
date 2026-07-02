class OutputStreamManager: NSObject, StreamDelegate {
  private let writeQueue = DispatchQueue(label: "de.eyev.writequeue")
  private var writeBuffer: [Data] = []
  private var canWrite = false
  private var isClosed = false
  private weak var outputStream: OutputStream?
  // Capture the runloop where streams are scheduled at init so deinit can
  // unschedule from the correct runloop regardless of which thread releases us.
  private let scheduledRunLoop: RunLoop

  init(outputStream: OutputStream) {
    self.outputStream = outputStream
    self.scheduledRunLoop = RunLoop.current
    super.init()
    self.outputStream?.delegate = self
    self.outputStream?.schedule(in: scheduledRunLoop, forMode: .default)
    self.outputStream?.open()
  }

  deinit {
    // Best-effort cleanup if close() was not called explicitly. close() should
    // have already torn down the stream and drained the queue.
    if !isClosed, let stream = outputStream {
      stream.close()
      stream.remove(from: scheduledRunLoop, forMode: .default)
      stream.delegate = nil
    }
  }

  /// Synchronously stop accepting writes, flush pending buffer, and tear down
  /// the stream. After this returns, no drainBuffer is in flight and no new
  /// writes will run. Must be called from the same thread that owns the
  /// session lifecycle (typically main) before releasing the EASession.
  func close() {
    writeQueue.sync {
      guard !isClosed else { return }
      isClosed = true
      writeBuffer.removeAll()
      if let stream = outputStream {
        stream.close()
        stream.remove(from: scheduledRunLoop, forMode: .default)
        stream.delegate = nil
      }
    }
  }

  func enqueueData(_ data: Data) {
    writeQueue.async { [weak self] in
      guard let self = self else { return }
      if self.isClosed { return }
      self.writeBuffer.append(data)
      self.drainBuffer()
    }
  }

  /// Write as much buffered data as possible. Must be called on writeQueue.
  /// Writes are gated on `canWrite`, which flips to true on `.hasSpaceAvailable`
  /// and back to false as soon as a write does not fully drain the current frame.
  private func drainBuffer() {
    if isClosed { return }
    guard let stream = outputStream, canWrite else { return }
    // Bail if the stream is no longer in a writable state. iAP2 may have
    // torn down the underlying USB endpoint already (e.g. on unplug) even if
    // the OutputStream object is still alive - writing into it then crashes.
    let status = stream.streamStatus
    if status == .error || status == .closed || status == .notOpen || status == .atEnd {
      canWrite = false
      return
    }
    while !writeBuffer.isEmpty {
      if isClosed { return }
      let data = writeBuffer[0]
      let written = data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Int in
        guard let baseAddress = buffer.baseAddress else { return 0 }
        let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)
        var total = 0
        while total < data.count {
          if !stream.hasSpaceAvailable { break }
          let s = stream.streamStatus
          if s == .error || s == .closed || s == .notOpen || s == .atEnd { break }
          let n = stream.write(ptr.advanced(by: total), maxLength: data.count - total)
          if n <= 0 { break }
          total += n
        }
        return total
      }
      if written == data.count {
        writeBuffer.removeFirst()
        if !stream.hasSpaceAvailable {
          canWrite = false
          return
        }
      } else if written > 0 {
        writeBuffer[0] = data.subdata(in: written..<data.count)
        canWrite = false
        return
      } else {
        canWrite = false
        return
      }
    }
  }

  public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
    switch eventCode {
    case .hasSpaceAvailable:
      writeQueue.async { [weak self] in
        guard let self = self else { return }
        if self.isClosed { return }
        self.canWrite = true
        self.drainBuffer()
      }
    case .errorOccurred:
      print("[OutputStreamManager] error: \(aStream.streamError?.localizedDescription ?? "unknown")")
      writeQueue.async { [weak self] in
        guard let self = self else { return }
        self.canWrite = false
      }
    case .endEncountered:
      print("[OutputStreamManager] stream ended")
      writeQueue.async { [weak self] in
        guard let self = self else { return }
        self.canWrite = false
      }
    default:
      break
    }
  }
}
