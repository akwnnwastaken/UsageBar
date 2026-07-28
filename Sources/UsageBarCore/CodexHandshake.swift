/// The JSON-RPC handshake UsageBar writes to `codex app-server` before asking
/// for the account quota. Kept pure and separate from the fetcher so what
/// actually goes on the wire can be inspected without launching Codex.
///
/// `clientInfo.version` is how UsageBar introduces itself to the app server, so
/// it must follow the running application's own version instead of a literal: a
/// hard-coded version survives a release bump unnoticed and makes the new build
/// announce itself as the previous one (that regression really shipped on the
/// Windows side as a stale `"1.9.0"`). The version is therefore always supplied
/// by the caller — this type deliberately has no version of its own.
public enum CodexHandshake {
    public static let clientName = "usage_bar"
    public static let clientTitle = "UsageBar"
    public static let initializeMethod = "initialize"
    public static let initializedMethod = "initialized"
    public static let rateLimitsMethod = "account/rateLimits/read"

    /// The `initialize` request, announcing `appVersion` as `clientInfo.version`.
    public static func initializeMessage(appVersion: String) -> String {
        "{\"method\":\"\(initializeMethod)\",\"id\":1,\"params\":{\"clientInfo\":"
            + "{\"name\":\"\(clientName)\",\"title\":\"\(clientTitle)\",\"version\":\"\(appVersion)\"}}}"
    }

    /// Every message UsageBar sends, in order. Request id 2 is the one
    /// `UsageParser.codexResponse` accepts as the usage answer.
    public static func messages(appVersion: String) -> [String] {
        [
            initializeMessage(appVersion: appVersion),
            "{\"method\":\"\(initializedMethod)\"}",
            "{\"method\":\"\(rateLimitsMethod)\",\"id\":2}"
        ]
    }

    /// The exact bytes written to the app server's stdin: newline-delimited
    /// messages, with a trailing newline so the last one is not left
    /// unterminated.
    public static func requestPayload(appVersion: String) -> String {
        messages(appVersion: appVersion).joined(separator: "\n") + "\n"
    }
}
