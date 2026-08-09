import Foundation

enum LocalUsageAPIHTTPStatus: Int, Equatable {
    case ok = 200
    case badRequest = 400
    case notFound = 404
    case methodNotAllowed = 405
    case contentTooLarge = 413
    case uriTooLong = 414
    case tooManyRequests = 429
    case requestHeaderFieldsTooLarge = 431
    case serviceUnavailable = 503
    case httpVersionNotSupported = 505

    var reasonPhrase: String {
        switch self {
        case .ok: "OK"
        case .badRequest: "Bad Request"
        case .notFound: "Not Found"
        case .methodNotAllowed: "Method Not Allowed"
        case .contentTooLarge: "Content Too Large"
        case .uriTooLong: "URI Too Long"
        case .tooManyRequests: "Too Many Requests"
        case .requestHeaderFieldsTooLarge: "Request Header Fields Too Large"
        case .serviceUnavailable: "Service Unavailable"
        case .httpVersionNotSupported: "HTTP Version Not Supported"
        }
    }
}

enum StrictHTTPRequestParseResult: Equatable {
    case incomplete
    case accepted
    case rejected(LocalUsageAPIHTTPStatus)
}

struct StrictHTTPRequestParser {
    static let maximumRequestLineBytes = 1_024
    static let maximumHeaderSectionBytes = 8_192
    static let maximumHeaderCount = 32
    static let maximumHeaderLineBytes = 1_024
    static let maximumBufferedRequestBytes = maximumRequestLineBytes + maximumHeaderSectionBytes + 1

    let expectedHost: String

    func parse(_ data: Data) -> StrictHTTPRequestParseResult {
        if containsBareLineFeed(in: data) || containsMalformedCarriageReturn(in: data) {
            return .rejected(.badRequest)
        }

        guard let requestLineEnd = data.firstRange(of: Self.crlf)?.lowerBound else {
            return data.count >= Self.maximumRequestLineBytes
                ? .rejected(.uriTooLong)
                : .incomplete
        }

        let requestLineBytes = requestLineEnd + Self.crlf.count
        guard requestLineBytes <= Self.maximumRequestLineBytes else {
            return .rejected(.uriTooLong)
        }

        let headerStart = requestLineBytes
        guard let headerTerminator = data.range(of: Self.headerTerminator, in: requestLineEnd..<data.count) else {
            return data.count - headerStart >= Self.maximumHeaderSectionBytes
                ? .rejected(.requestHeaderFieldsTooLarge)
                : .incomplete
        }

        let headerEnd = headerTerminator.upperBound
        guard headerEnd - headerStart <= Self.maximumHeaderSectionBytes else {
            return .rejected(.requestHeaderFieldsTooLarge)
        }

        guard let requestLine = asciiString(data[0..<requestLineEnd]) else {
            return .rejected(.badRequest)
        }
        let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: false)
        guard requestParts.count == 3,
              !requestParts[0].isEmpty,
              !requestParts[1].isEmpty,
              !requestParts[2].isEmpty,
              requestParts.allSatisfy({ !$0.contains("\t") }),
              isToken(String(requestParts[0]))
        else {
            return .rejected(.badRequest)
        }

        let method = String(requestParts[0])
        let target = String(requestParts[1])
        let version = String(requestParts[2])
        guard isSyntacticallyValidHTTPVersion(version) else {
            return .rejected(.badRequest)
        }
        guard version == "HTTP/1.1" else {
            return .rejected(.httpVersionNotSupported)
        }

        let headerPayloadEnd = headerTerminator.lowerBound
        var cursor = headerStart
        var headers: [(name: String, value: String)] = []
        while cursor < headerPayloadEnd {
            guard let lineEnd = data.range(of: Self.crlf, in: cursor..<headerTerminator.upperBound)?.lowerBound,
                  lineEnd <= headerPayloadEnd
            else {
                return .rejected(.badRequest)
            }
            let lineByteCount = lineEnd - cursor + Self.crlf.count
            guard lineByteCount <= Self.maximumHeaderLineBytes else {
                return .rejected(.requestHeaderFieldsTooLarge)
            }
            guard let line = asciiString(data[cursor..<lineEnd]),
                  !line.isEmpty,
                  !line.first!.isWhitespace,
                  let colon = line.firstIndex(of: ":")
            else {
                return .rejected(.badRequest)
            }

            let name = String(line[..<colon])
            guard isToken(name) else {
                return .rejected(.badRequest)
            }
            var value = String(line[line.index(after: colon)...])
            if value.first == " " {
                value.removeFirst()
            }
            guard !value.isEmpty || name.caseInsensitiveCompare("Content-Length") == .orderedSame,
                  !value.hasPrefix(" "),
                  !value.hasSuffix(" "),
                  value.utf8.allSatisfy({ $0 >= 0x20 && $0 <= 0x7e })
            else {
                return .rejected(.badRequest)
            }
            headers.append((name, value))
            guard headers.count <= Self.maximumHeaderCount else {
                return .rejected(.requestHeaderFieldsTooLarge)
            }
            cursor = lineEnd + Self.crlf.count
        }

        let hosts = values(named: "Host", in: headers)
        guard hosts.count == 1, hosts[0] == expectedHost else {
            return .rejected(.badRequest)
        }
        guard values(named: "Origin", in: headers).isEmpty else {
            return .rejected(.badRequest)
        }
        let fetchSites = values(named: "Sec-Fetch-Site", in: headers)
        guard fetchSites.count <= 1, fetchSites.first == nil || fetchSites.first == "none" else {
            return .rejected(.badRequest)
        }

        guard values(named: "Transfer-Encoding", in: headers).isEmpty else {
            return .rejected(.badRequest)
        }
        let contentLengths = values(named: "Content-Length", in: headers)
        guard contentLengths.count <= 1 else {
            return .rejected(.badRequest)
        }
        if let contentLength = contentLengths.first {
            guard !contentLength.isEmpty,
                  contentLength.allSatisfy({ $0.isASCII && $0.isNumber })
            else {
                return .rejected(.badRequest)
            }
            if contentLength == "0" {
                // The only body framing accepted by the frozen protocol.
            } else if contentLength.first == "0" {
                return .rejected(.badRequest)
            } else if UInt64(contentLength) != nil {
                return .rejected(.contentTooLarge)
            } else {
                return .rejected(.badRequest)
            }
        }

        guard data.count == headerEnd else {
            return .rejected(.badRequest)
        }
        guard method == "GET" else {
            return .rejected(.methodNotAllowed)
        }
        guard target == "/v1/usage" else {
            return .rejected(.notFound)
        }
        return .accepted
    }

    private func values(named expectedName: String, in headers: [(name: String, value: String)]) -> [String] {
        headers.compactMap { header in
            header.name.caseInsensitiveCompare(expectedName) == .orderedSame ? header.value : nil
        }
    }

    private func isToken(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { byte in
            switch byte {
            case 0x21, 0x23...0x27, 0x2a, 0x2b, 0x2d, 0x2e,
                 0x30...0x39, 0x41...0x5a, 0x5e...0x7a, 0x7c, 0x7e:
                true
            default:
                false
            }
        }
    }

    private func isSyntacticallyValidHTTPVersion(_ value: String) -> Bool {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == "HTTP" else { return false }
        let numbers = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        return numbers.count == 2
            && !numbers[0].isEmpty
            && !numbers[1].isEmpty
            && numbers[0].allSatisfy(\.isNumber)
            && numbers[1].allSatisfy(\.isNumber)
    }

    private func containsBareLineFeed(in data: Data) -> Bool {
        for index in data.indices where data[index] == 0x0a {
            if index == data.startIndex || data[data.index(before: index)] != 0x0d {
                return true
            }
        }
        return false
    }

    private func containsMalformedCarriageReturn(in data: Data) -> Bool {
        for index in data.indices where data[index] == 0x0d {
            let next = data.index(after: index)
            if next < data.endIndex && data[next] != 0x0a {
                return true
            }
        }
        return false
    }

    private func asciiString(_ bytes: Data.SubSequence) -> String? {
        String(data: Data(bytes), encoding: .ascii)
    }

    private static let crlf = Data([0x0d, 0x0a])
    private static let headerTerminator = Data([0x0d, 0x0a, 0x0d, 0x0a])
}

private extension Data {
    func firstRange(of needle: Data) -> Range<Int>? {
        range(of: needle, options: [], in: startIndex..<endIndex)
    }
}
