import Foundation
import XCTest
@testable import UsageBarLocalAPI

final class LocalUsageAPIStrictHTTPRequestParserTests: XCTestCase {
    private let parser = StrictHTTPRequestParser(expectedHost: "127.0.0.1:54132")

    func testExactGETHostAndBrowserMetadataPolicy() {
        XCTAssertEqual(parser.parse(request()), .accepted)
        XCTAssertEqual(parser.parse(request(headers: ["Host: 127.0.0.1:54132", "Sec-Fetch-Site: none"])), .accepted)

        for host in [nil, "localhost:54132", "127.0.0.1", "127.0.0.1:1", "[::1]:54132", "2130706433:54132", " 127.0.0.1:54132", "127.0.0.1:54132 "] {
            let headers = host.map { ["Host: \($0)"] } ?? []
            XCTAssertEqual(parser.parse(request(headers: headers)), .rejected(.badRequest))
        }
        XCTAssertEqual(
            parser.parse(request(headers: ["Host: 127.0.0.1:54132", "Host: 127.0.0.1:54132"])),
            .rejected(.badRequest)
        )
        XCTAssertEqual(
            parser.parse(request(headers: ["Host: 127.0.0.1:54132", "Origin: https://example.invalid"])),
            .rejected(.badRequest)
        )
        for value in ["same-origin", "same-site", "cross-site", "None"] {
            XCTAssertEqual(
                parser.parse(request(headers: ["Host: 127.0.0.1:54132", "Sec-Fetch-Site: \(value)"])),
                .rejected(.badRequest)
            )
        }
    }

    func testOnlyGETExactTargetAndHTTP11AreAccepted() {
        for method in ["HEAD", "POST", "PUT", "DELETE", "OPTIONS", "TRACE", "CONNECT", "PATCH"] {
            XCTAssertEqual(parser.parse(request(method: method)), .rejected(.methodNotAllowed), method)
        }
        for target in ["/v1/usage/", "/v1/usage?x=y", "/v1/usage#", "/v1/health", "*", "example.invalid:80", "http://127.0.0.1:54132/v1/usage"] {
            XCTAssertEqual(parser.parse(request(target: target)), .rejected(.notFound), target)
        }
        for version in ["HTTP/1.0", "HTTP/2.0", "HTTP/3.0"] {
            XCTAssertEqual(parser.parse(request(version: version)), .rejected(.httpVersionNotSupported), version)
        }
        for line in [
            "GET  /v1/usage HTTP/1.1\r\nHost: 127.0.0.1:54132\r\n\r\n",
            "GET\t/v1/usage HTTP/1.1\r\nHost: 127.0.0.1:54132\r\n\r\n",
            "GET /v1/usage NOTHTTP\r\nHost: 127.0.0.1:54132\r\n\r\n",
            "GE(T /v1/usage HTTP/1.1\r\nHost: 127.0.0.1:54132\r\n\r\n"
        ] {
            XCTAssertEqual(parser.parse(Data(line.utf8)), .rejected(.badRequest))
        }
    }

    func testRequestLineBoundaryIsExact() {
        let fixedCount = " /v1/usage HTTP/1.1\r\n".utf8.count
        let exactMethod = String(repeating: "G", count: StrictHTTPRequestParser.maximumRequestLineBytes - fixedCount)
        XCTAssertEqual(parser.parse(request(method: exactMethod)), .rejected(.methodNotAllowed))
        XCTAssertEqual(parser.parse(request(method: exactMethod + "G")), .rejected(.uriTooLong))

        let incomplete = Data(String(repeating: "G", count: StrictHTTPRequestParser.maximumRequestLineBytes).utf8)
        XCTAssertEqual(parser.parse(incomplete), .rejected(.uriTooLong))
    }

    func testHeaderLineCountAndSectionBoundariesAreExact() throws {
        let exactLineValueCount = StrictHTTPRequestParser.maximumHeaderLineBytes - "X-Fill: ".utf8.count - 2
        let exactLine = "X-Fill: " + String(repeating: "a", count: exactLineValueCount)
        XCTAssertEqual(parser.parse(request(headers: ["Host: 127.0.0.1:54132", exactLine])), .accepted)
        XCTAssertEqual(parser.parse(request(headers: ["Host: 127.0.0.1:54132", exactLine + "a"])), .rejected(.requestHeaderFieldsTooLarge))

        let thirtyTwo = ["Host: 127.0.0.1:54132"] + (1..<32).map { "X-\($0): a" }
        XCTAssertEqual(parser.parse(request(headers: thirtyTwo)), .accepted)
        XCTAssertEqual(parser.parse(request(headers: thirtyTwo + ["X-32: a"])), .rejected(.requestHeaderFieldsTooLarge))

        let exactSection = try requestWithHeaderSectionSize(StrictHTTPRequestParser.maximumHeaderSectionBytes)
        XCTAssertEqual(parser.parse(exactSection), .accepted)
        let oversizedSection = try requestWithHeaderSectionSize(StrictHTTPRequestParser.maximumHeaderSectionBytes + 1)
        XCTAssertEqual(parser.parse(oversizedSection), .rejected(.requestHeaderFieldsTooLarge))
    }

    func testZeroBodyAndFramingPolicy() {
        XCTAssertEqual(parser.parse(request()), .accepted)
        XCTAssertEqual(parser.parse(request(headers: ["Host: 127.0.0.1:54132", "Content-Length: 0"])), .accepted)
        XCTAssertEqual(parser.parse(request(headers: ["Host: 127.0.0.1:54132", "Content-Length: 1"])), .rejected(.contentTooLarge))

        for value in ["", "+0", "-0", "00", "0, 0", "18446744073709551616", " 0", "0 "] {
            XCTAssertEqual(
                parser.parse(request(headers: ["Host: 127.0.0.1:54132", "Content-Length: \(value)"])),
                .rejected(.badRequest),
                value
            )
        }
        XCTAssertEqual(
            parser.parse(request(headers: ["Host: 127.0.0.1:54132", "Content-Length: 0", "Content-Length: 0"])),
            .rejected(.badRequest)
        )
        XCTAssertEqual(
            parser.parse(request(headers: ["Host: 127.0.0.1:54132", "Transfer-Encoding: chunked"])),
            .rejected(.badRequest)
        )
        XCTAssertEqual(
            parser.parse(request(headers: ["Host: 127.0.0.1:54132", "Transfer-Encoding: chunked", "Content-Length: 0"])),
            .rejected(.badRequest)
        )
        XCTAssertEqual(parser.parse(request(body: "x")), .rejected(.badRequest))
        XCTAssertEqual(parser.parse(request(body: "GET /v1/usage HTTP/1.1\r\nHost: 127.0.0.1:54132\r\n\r\n")), .rejected(.badRequest))
    }

    func testMalformedAndAmbiguousHeadersAreRejected() {
        let malformed = [
            "GET /v1/usage HTTP/1.1\nHost: 127.0.0.1:54132\n\n",
            "GET /v1/usage HTTP/1.1\r\nHost: 127.0.0.1:54132\r\n folded\r\n\r\n",
            "GET /v1/usage HTTP/1.1\r\nBad Name: x\r\nHost: 127.0.0.1:54132\r\n\r\n",
            "GET /v1/usage HTTP/1.1\r\nHost : 127.0.0.1:54132\r\n\r\n",
            "GET /v1/usage HTTP/1.1\rX-Thing: x\r\n\r\n",
            "GET /v1/usage HTTP/1.1\r\nHost:\t127.0.0.1:54132\r\n\r\n",
            "GET /v1/usage HTTP/1.1\r\nHost: 127.0.0.1:54132\u{7f}\r\n\r\n",
            "GET /v1/usage HTTP/1.1\r\nHost: 127.0.0.1:54132, example.invalid\r\n\r\n"
        ]
        for value in malformed {
            XCTAssertEqual(parser.parse(Data(value.utf8)), .rejected(.badRequest))
        }
    }

    func testIncompleteRequestRemainsBounded() {
        XCTAssertEqual(parser.parse(Data("GET /v1/usage HTTP/1.1\r\nHost: 127.0.0.1:54132".utf8)), .incomplete)
        let oversizedHeaders = "GET /v1/usage HTTP/1.1\r\n" + String(repeating: "X", count: StrictHTTPRequestParser.maximumHeaderSectionBytes)
        XCTAssertEqual(parser.parse(Data(oversizedHeaders.utf8)), .rejected(.requestHeaderFieldsTooLarge))
    }

    private func request(
        method: String = "GET",
        target: String = "/v1/usage",
        version: String = "HTTP/1.1",
        headers: [String] = ["Host: 127.0.0.1:54132"],
        body: String = ""
    ) -> Data {
        Data((["\(method) \(target) \(version)"] + headers + ["", ""]).joined(separator: "\r\n").utf8)
            + Data(body.utf8)
    }

    private func requestWithHeaderSectionSize(_ requestedSize: Int) throws -> Data {
        var lines = ["Host: 127.0.0.1:54132"]
        var currentSize = lines[0].utf8.count + 2 + 2
        var index = 0
        while currentSize < requestedSize {
            let prefix = "X-\(index): "
            let available = min(
                StrictHTTPRequestParser.maximumHeaderLineBytes - prefix.utf8.count - 2,
                requestedSize - currentSize - prefix.utf8.count - 2
            )
            guard available >= 1 else {
                throw TestError.cannotBuildBoundary
            }
            lines.append(prefix + String(repeating: "a", count: available))
            currentSize += prefix.utf8.count + available + 2
            index += 1
        }
        XCTAssertEqual(currentSize, requestedSize)
        return request(headers: lines)
    }

    private enum TestError: Error {
        case cannotBuildBoundary
    }
}
