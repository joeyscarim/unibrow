actor ThumbnailLoadLimiter {
    private var inFlight = 0
    private let limit = 3
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if inFlight < limit {
            inFlight += 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            inFlight = max(0, inFlight - 1)
        }
    }
}
