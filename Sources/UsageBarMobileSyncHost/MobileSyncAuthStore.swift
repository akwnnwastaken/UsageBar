import Foundation
import Security

/// Where the Mac keeps the mobile auth record.
///
/// Abstracted so the auth lifecycle can be tested without touching the login
/// keychain, and so a test can never leave a stray item behind on a developer's
/// machine.
///
/// `Sendable` because the request policy reads it from the listener's
/// connection queues while the menu writes it from the main queue. Every
/// conformance below therefore carries its own synchronization rather than
/// relying on a caller to serialize access.
public protocol MobileSyncAuthStoring: AnyObject, Sendable {
    func load() -> MobileSyncAuthRecord?
    func save(_ record: MobileSyncAuthRecord) throws
    func clear()
}

/// Keychain-backed storage, in a lab-only service namespace.
///
/// Only digests land here. `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` keeps
/// the item out of iCloud Keychain and out of a migration to another Mac: the
/// record authorizes one phone against *this* host, and a copy of it on another
/// machine would be meaningless at best.
public final class MobileSyncKeychainAuthStore: MobileSyncAuthStoring, @unchecked Sendable {
    public enum StoreError: Error, Equatable, CustomStringConvertible {
        case unexpectedStatus(OSStatus)
        /// Deliberately vague; an OSStatus is for a developer, not a menu.
        public var description: String { "The pairing could not be saved securely." }
    }

    private let service: String
    private let account = "mobile-auth-v1"

    public init(service: String = MobileSyncIdentity.keychainService) {
        self.service = service
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    public func load() -> MobileSyncAuthRecord? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return MobileSyncAuthRecord.decode(data)
    }

    public func save(_ record: MobileSyncAuthRecord) throws {
        // Delete-then-add: one code path rather than two, and it cannot leave a
        // stale attribute from a previous pairing behind.
        SecItemDelete(baseQuery as CFDictionary)
        var query = baseQuery
        query[kSecValueData as String] = record.encoded()
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw StoreError.unexpectedStatus(status) }
    }

    public func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

/// In-memory store for tests.
public final class InMemoryMobileSyncAuthStore: MobileSyncAuthStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var record: MobileSyncAuthRecord?
    private var saves = 0
    private var clears = 0

    public init(record: MobileSyncAuthRecord? = nil) {
        self.record = record
    }

    public var saveCount: Int { lock.lock(); defer { lock.unlock() }; return saves }
    public var clearCount: Int { lock.lock(); defer { lock.unlock() }; return clears }

    public func load() -> MobileSyncAuthRecord? {
        lock.lock(); defer { lock.unlock() }
        return record
    }

    public func save(_ record: MobileSyncAuthRecord) throws {
        lock.lock(); defer { lock.unlock() }
        saves += 1
        self.record = record
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        clears += 1
        record = nil
    }
}
