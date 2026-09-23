import Foundation
import UsageBarSyncTransport
@testable import UsageBarMobileSyncHost

/// Request builders for the host's routes.
enum HostRequests {
    static func snapshot(
        bearer: String? = nil,
        identity: String? = HostFixtures.identity,
        method: String = "GET",
        path: String = MobileSyncService.snapshotPath
    ) -> UsageSyncTransportRequest {
        var headers: [String: String] = [:]
        if let identity { headers[MobileSyncService.identityHeader] = identity }
        if let bearer { headers["Authorization"] = "Bearer \(bearer)" }
        return UsageSyncTransportRequest(method: method, path: path, headers: headers)
    }

    static func pair(
        code: String? = nil,
        identity: String? = HostFixtures.identity,
        method: String = "POST",
        path: String = MobileSyncService.pairingPath,
        scheme: String = MobileSyncService.pairingAuthorizationScheme
    ) -> UsageSyncTransportRequest {
        var headers: [String: String] = [:]
        if let identity { headers[MobileSyncService.identityHeader] = identity }
        if let code { headers["Authorization"] = "\(scheme) \(code)" }
        return UsageSyncTransportRequest(method: method, path: path, headers: headers)
    }
}

extension UsageSyncTransportResponse {
    var bodyText: String { String(decoding: body, as: UTF8.self) }

    var jsonObject: [String: Any]? {
        (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    }
}
