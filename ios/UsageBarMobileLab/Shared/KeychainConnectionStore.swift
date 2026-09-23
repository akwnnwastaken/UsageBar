import Foundation
import Security

/// Everything the app needs to reach the desktop.
///
/// Both halves are runtime configuration. Neither is ever compiled in, and the
/// host is treated as secret alongside the key: a MagicDNS name identifies a
/// machine on a private tailnet and is frequently derived from its owner, so it
/// is personal metadata rather than a harmless address.
public struct UsageSyncConnection: Equatable, Sendable {
    public let host: UsageSyncHost
    public let accessKey: String

    public init(host: UsageSyncHost, accessKey: String) {
        self.host = host
        self.accessKey = accessKey
    }
}

/// What the store can currently say about the connection.
///
/// The third case is the one that matters. A keychain read can fail because
/// nothing is stored, or because the device is locked and the item is simply
/// not reachable right now — and those mean opposite things. Collapsing them
/// into `nil` would make a locked phone indistinguishable from a forgotten
/// connection, and the widget's revocation rule would then delete a perfectly
/// good cached snapshot every time the screen went off.
public enum ConnectionAvailability: Equatable {
    case available(UsageSyncConnection)
    /// Nothing is stored. This is revocation: the surfaces must forget.
    case missing
    /// Something is stored but cannot be read right now, almost always because
    /// the device is locked. Not revocation, and never treated as one.
    case temporarilyUnavailable
}

/// Persistence for the connection. Abstracted so tests do not need a keychain
/// and so a later checkpoint can change where this lives without touching the
/// networking or UI layers.
public protocol ConnectionStore: AnyObject {
    func availability() -> ConnectionAvailability
    func save(_ connection: UsageSyncConnection) throws
    func clear()
}

public extension ConnectionStore {
    /// The connection when there is one to be had.
    ///
    /// Deliberately lossy, and only for callers that genuinely cannot act on
    /// the distinction — the app in the foreground, where the device is
    /// unlocked by definition. Anything that decides whether to *revoke*
    /// must read `availability()` instead.
    func load() -> UsageSyncConnection? {
        guard case .available(let connection) = availability() else { return nil }
        return connection
    }
}

/// Keychain-backed store.
///
/// The access key is a credential and the host is private tailnet metadata, so
/// both live in the keychain rather than `UserDefaults` or a plist — neither of
/// which is encrypted at rest, and both of which land in device backups and
/// sysdiagnose captures.
///
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` is chosen deliberately:
/// `ThisDeviceOnly` keeps the items out of backups and off other devices, and
/// `WhenUnlocked` is sufficient because Phase 5 refreshes only in the
/// foreground at the user's request. When background refresh arrives it will
/// need this decision revisited rather than silently loosened.
public final class KeychainConnectionStore: ConnectionStore {
    public enum StoreError: Error, Equatable, CustomStringConvertible {
        case unexpectedStatus(OSStatus)

        public var description: String {
            // Deliberately vague; an OSStatus is for the developer, not a screen.
            "The connection could not be saved securely."
        }
    }

    private let service: String
    private let hostAccount = "tailscale-host"
    private let keyAccount = "access-key"

    public init(service: String = "com.usagebar.mobilelab.connection") {
        self.service = service
    }

    public func availability() -> ConnectionAvailability {
        let hostResult = readString(account: hostAccount)
        let keyResult = readString(account: keyAccount)

        // Locked wins over missing. If either half of the pair is unreadable
        // because the device is locked, the honest answer is "ask again later",
        // not "there is nothing here" — even if the other half happened to be
        // readable.
        if case .locked = hostResult { return .temporarilyUnavailable }
        if case .locked = keyResult { return .temporarilyUnavailable }

        guard case .value(let hostValue) = hostResult,
              case .value(let accessKey) = keyResult,
              let host = try? UsageSyncHost(validating: hostValue) else {
            return .missing
        }
        return .available(UsageSyncConnection(host: host, accessKey: accessKey))
    }

    public func save(_ connection: UsageSyncConnection) throws {
        try write(connection.host.value, account: hostAccount)
        try write(connection.accessKey, account: keyAccount)
    }

    public func clear() {
        for account in [hostAccount, keyAccount] {
            SecItemDelete(baseQuery(account: account) as CFDictionary)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    /// A keychain read, with "locked" kept separate from "absent".
    private enum ReadResult {
        case value(String)
        case absent
        /// The item exists but the class is not available right now. With
        /// `WhenUnlockedThisDeviceOnly` this is what a locked device returns,
        /// and it must never be mistaken for deletion.
        case locked
    }

    private func readString(account: String) -> ReadResult {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let text = String(data: data, encoding: .utf8) else { return .absent }
            return .value(text)
        case errSecItemNotFound:
            return .absent
        case errSecInteractionNotAllowed:
            return .locked
        default:
            // An unexpected status is not evidence of deletion either. Erring
            // towards "try again later" costs a refresh; erring the other way
            // costs the user their connection.
            return .locked
        }
    }

    private func write(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        // Delete-then-add rather than update: it is one code path instead of
        // two, and it cannot leave a stale attribute from a previous write.
        SecItemDelete(baseQuery(account: account) as CFDictionary)

        var query = baseQuery(account: account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw StoreError.unexpectedStatus(status)
        }
    }
}

/// In-memory store for tests and previews.
public final class InMemoryConnectionStore: ConnectionStore {
    private var connection: UsageSyncConnection?
    /// Simulates a locked device without one.
    public var isTemporarilyUnavailable = false
    public private(set) var clearCount = 0

    public init(connection: UsageSyncConnection? = nil, isTemporarilyUnavailable: Bool = false) {
        self.connection = connection
        self.isTemporarilyUnavailable = isTemporarilyUnavailable
    }

    public func availability() -> ConnectionAvailability {
        if isTemporarilyUnavailable { return .temporarilyUnavailable }
        guard let connection else { return .missing }
        return .available(connection)
    }

    public func save(_ connection: UsageSyncConnection) throws { self.connection = connection }

    public func clear() {
        clearCount += 1
        connection = nil
    }
}
