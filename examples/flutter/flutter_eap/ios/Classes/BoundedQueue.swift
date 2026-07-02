public class BoundedQueue<T> {
  private var queue: [T] = []
  private let accessQueue = DispatchQueue(label: "de.eyev.boundedqueue")
  private let semaphore: DispatchSemaphore
  private let maxSize: Int
  
  init(maxSize: Int) {
    self.maxSize = maxSize
    self.semaphore = DispatchSemaphore(value: 0)
  }
  
  func enqueue(_ item: T) {
    accessQueue.sync {
      if queue.count == maxSize {
        _ = queue.removeFirst()  // Remove the oldest item if the queue is full
      }
      queue.append(item)
      semaphore.signal()  // Signal that there is a new item available
    }
  }
  
  func dequeue() -> T? {
    semaphore.wait()  // Wait until an item is available
    return accessQueue.sync {
      queue.isEmpty ? nil : queue.removeFirst()
    }
  }
  
  func clear() {
    accessQueue.sync { queue.removeAll() }
  }
  
  var isCompleted: Bool {
    accessQueue.sync { queue.isEmpty }
  }
  
  var count: Int {
    accessQueue.sync { queue.count }
  }
  
  var isEmpty: Bool {
    accessQueue.sync { queue.isEmpty }
  }
}
