import Foundation
import UsageBarPairing
import UsageBarSync

/// Exchanges a one-time pairing code for the long-lived access key.
public protocol PairingExchanging: Sendable {
    func exchange(payload: UsageBarPairingPayload) async throws -> PairedConnection
}

/// What a successful exchange produced, before anything is persisted.
public struct PairedConnection: Equatable, Sendable {
    public let host: UsageSyncHost
    public let accessKey: String

    public init(host: UsageSyncHost, accessKey: String) {
        self.host = host
        self.accessKey = accessKey
    }

    public var connection: UsageSyncConnection {
        UsageSyncConnection(host: host, accessKey: accessKey)
    }
}

public enum PairingError: Error, Equatable, CustomStringConvertible {
    case invalidCode
    case refused
    case transportFailure
    case malformedResponse

    /// One sentence for every case.
    ///
    /// A pairing failure is read by someone standing in front of their own Mac,
    /// and telling them *which* part of a forged or stale QR nearly worked
    /// would help a bystander far more than it helps them.
    public var description: String {
        "Pairing failed. Show a new code on your Mac and try again."
    }
}

/// The pairing half of the client.
///
/// Same transport rules as the snapshot fetch, for the same reasons: system
/// TLS, no redirects, no cookies, no URL cache, finite timeouts and a hard
/// ceiling on the response. The endpoint is a hostname that arrived in a QR,
/// which is barely more trusted than one a user typed.
public final class UsageSyncPairingClient: NSObject, PairingExchanging, @unchecked Sendable {
    /// A pairing response is two short fields. 4 KiB is already generous, and
    /// far below the snapshot ceiling because nothing large belongs here.
    public static let maximumResponseBytes = 4 * 1024

    private let configuration: URLSessionConfiguration
    private let requestTimeout: TimeInterval

    public init(
        configuration: URLSessionConfiguration = UsageSyncAPIClient.privateConfiguration(),
        requestTimeout: TimeInterval = 15
    ) {
        self.configuration = configuration
        self.requestTimeout = requestTimeout
        super.init()
    }

    public func exchange(payload: UsageBarPairingPayload) async throws -> PairedConnection {
        // The payload's own structural check is not enough to build a URL from.
        // The endpoint validator is the authoritative one, and it runs here,
        // before anything is requested.
        guard let host = try? UsageSyncHost(validating: payload.host) else {
            throw PairingError.invalidCode
        }

        var request = URLRequest(url: host.pairingURL)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // The code travels in a header under its own scheme — never in the URL,
        // the query string or the path, all of which are logged by proxies and
        // kept in history. There is no body at all, so there is nowhere else it
        // could be.
        request.setValue(
            "UsageBar-Pair \(payload.pairingCode.encoded)",
            forHTTPHeaderField: "Authorization"
        )
        // No Tailscale identity header, here or anywhere. Serve injects one;
        // a client that set it would be asserting an identity rather than
        // proving it.

        let delegate = SnapshotTaskDelegate(maximumBytes: Self.maximumResponseBytes)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await delegate.perform(request: request, on: session)
        } catch {
            throw PairingError.transportFailure
        }

        guard let http = response as? HTTPURLResponse else { throw PairingError.transportFailure }
        guard http.statusCode == 200 else { throw PairingError.refused }
        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        guard contentType.hasPrefix("application/json") else { throw PairingError.malformedResponse }
        guard data.count <= Self.maximumResponseBytes else { throw PairingError.malformedResponse }

        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              dictionary["schemaVersion"] as? Int == 1,
              let accessKey = dictionary["accessKey"] as? String,
              !accessKey.isEmpty,
              accessKey.utf8.count <= 256
        else { throw PairingError.malformedResponse }

        return PairedConnection(host: host, accessKey: accessKey)
    }
}
