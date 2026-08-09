import Foundation

struct LocalUsageAPIHTTPResponseBuilder {
    func build(status: LocalUsageAPIHTTPStatus, body: Data = Data(), date: Date) -> Data {
        let responseBody = status == .ok ? body : Data()
        var lines = [
            "HTTP/1.1 \(status.rawValue) \(status.reasonPhrase)",
            "Date: \(Self.httpDate(date))"
        ]
        if status == .ok {
            lines.append("Content-Type: application/json; charset=utf-8")
        }
        lines.append("Content-Length: \(responseBody.count)")
        lines.append("Connection: close")
        lines.append("Cache-Control: no-store")
        lines.append("X-Content-Type-Options: nosniff")
        if status == .methodNotAllowed {
            lines.append("Allow: GET")
        }
        if status == .tooManyRequests {
            lines.append("Retry-After: 1")
        }
        lines.append("")
        lines.append("")

        var result = Data(lines.joined(separator: "\r\n").utf8)
        result.append(responseBody)
        return result
    }

    static func httpDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: date)
    }
}

final class LocalUsageAPITokenBucket {
    private let lock = NSLock()
    private let rate: Double
    private let capacity: Double
    private var tokens: Double
    private var lastMonotonicTime: TimeInterval

    init(ratePerSecond: Double = 4, burst: Int = 8, initialMonotonicTime: TimeInterval) {
        precondition(ratePerSecond > 0)
        precondition(burst > 0)
        rate = ratePerSecond
        capacity = Double(burst)
        tokens = Double(burst)
        lastMonotonicTime = initialMonotonicTime
    }

    func admit(at monotonicTime: TimeInterval) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let elapsed = max(0, monotonicTime - lastMonotonicTime)
        tokens = min(capacity, tokens + elapsed * rate)
        lastMonotonicTime = max(lastMonotonicTime, monotonicTime)
        guard tokens >= 1 else { return false }
        tokens -= 1
        return true
    }
}

final class LocalUsageAPIActiveConnectionGate {
    private let lock = NSLock()
    private let maximum: Int
    private var active = 0

    init(maximum: Int = 4) {
        precondition(maximum > 0)
        self.maximum = maximum
    }

    func acquire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard active < maximum else { return false }
        active += 1
        return true
    }

    func release() {
        lock.lock()
        defer { lock.unlock() }
        precondition(active > 0)
        active -= 1
    }

    var activeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return active
    }
}

protocol LocalUsageAPIDeadlineToken: AnyObject {
    func cancel()
}

protocol LocalUsageAPIDeadlineScheduling {
    func schedule(after delay: TimeInterval, action: @escaping () -> Void) -> LocalUsageAPIDeadlineToken
}

final class DispatchLocalUsageAPIDeadlineScheduler: LocalUsageAPIDeadlineScheduling {
    private let queue: DispatchQueue

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func schedule(after delay: TimeInterval, action: @escaping () -> Void) -> LocalUsageAPIDeadlineToken {
        let item = DispatchWorkItem(block: action)
        queue.asyncAfter(deadline: .now() + delay, execute: item)
        return DispatchDeadlineToken(item: item)
    }
}

private final class DispatchDeadlineToken: LocalUsageAPIDeadlineToken {
    private let item: DispatchWorkItem

    init(item: DispatchWorkItem) {
        self.item = item
    }

    func cancel() {
        item.cancel()
    }
}

final class LocalUsageAPIAbsoluteDeadline {
    private let delay: TimeInterval
    private let scheduler: LocalUsageAPIDeadlineScheduling
    private var token: LocalUsageAPIDeadlineToken?

    init(delay: TimeInterval, scheduler: LocalUsageAPIDeadlineScheduling) {
        self.delay = delay
        self.scheduler = scheduler
    }

    func start(action: @escaping () -> Void) {
        guard token == nil else { return }
        token = scheduler.schedule(after: delay, action: action)
    }

    func cancel() {
        token?.cancel()
        token = nil
    }
}

final class LocalUsageAPIRequestProcessor {
    typealias SnapshotProvider = (Date, @escaping (Result<Data, Error>) -> Void) -> Void

    static let maximumResponseBodyBytes = 16 * 1_024

    private let parser: StrictHTTPRequestParser
    private let responseBuilder: LocalUsageAPIHTTPResponseBuilder
    private let wallNow: () -> Date
    private let snapshotProvider: SnapshotProvider

    init(
        expectedHost: String,
        wallNow: @escaping () -> Date,
        snapshotProvider: @escaping SnapshotProvider
    ) {
        parser = StrictHTTPRequestParser(expectedHost: expectedHost)
        responseBuilder = LocalUsageAPIHTTPResponseBuilder()
        self.wallNow = wallNow
        self.snapshotProvider = snapshotProvider
    }

    @discardableResult
    func process(_ request: Data, completion: @escaping (Data) -> Void) -> Bool {
        switch parser.parse(request) {
        case .incomplete:
            return false
        case let .rejected(status):
            completion(responseBuilder.build(status: status, date: wallNow()))
            return true
        case .accepted:
            let observedAt = wallNow()
            snapshotProvider(observedAt) { result in
                let response: Data
                switch result {
                case let .success(body) where body.count <= Self.maximumResponseBodyBytes:
                    response = self.responseBuilder.build(status: .ok, body: body, date: observedAt)
                case .success, .failure:
                    response = self.responseBuilder.build(status: .serviceUnavailable, date: observedAt)
                }
                completion(response)
            }
            return true
        }
    }

    func response(status: LocalUsageAPIHTTPStatus) -> Data {
        responseBuilder.build(status: status, date: wallNow())
    }
}
