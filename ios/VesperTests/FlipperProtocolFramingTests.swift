import XCTest
@testable import Vesper

final class FlipperParsingTests: XCTestCase {

    func testStripAnsiRemovesEscapesAndCR() {
        let input = "\u{1B}[32mhello\u{1B}[0m\r\nworld"
        XCTAssertEqual(FlipperProtocol.stripAnsi(input), "hello\nworld")
    }

    func testParseListSeparatesFilesAndDirectories() {
        let output = """
        [D] subghz
        [D] infrared
        [F] readme.txt 1024
        [F] my file.sub 2048
        """
        let entries = FlipperFileSystem.parseList(output, base: "/ext")
        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(entries[0].name, "subghz")
        XCTAssertTrue(entries[0].isDirectory)
        XCTAssertEqual(entries[2].name, "readme.txt")
        XCTAssertEqual(entries[2].sizeBytes, 1024)
        XCTAssertEqual(entries[3].name, "my file.sub")
        XCTAssertEqual(entries[3].sizeBytes, 2048)
        XCTAssertEqual(entries[3].path, "/ext/my file.sub")
    }

    func testParseKeyValues() {
        let output = "hardware_name      : Zero\nfirmware_version   : 1.2.3\ncharge_level: 88"
        let kv = FlipperFileSystem.parseKeyValues(output)
        XCTAssertEqual(kv["hardware_name"], "Zero")
        XCTAssertEqual(kv["firmware_version"], "1.2.3")
        XCTAssertEqual(kv["charge_level"], "88")
    }

    func testParseStorageInfoComputesUsed() {
        let output = "1000 KB total\n400 KB free"
        let (used, total) = FlipperFileSystem.parseStorageInfo(output)
        XCTAssertEqual(total, 1000 * 1024)
        XCTAssertEqual(used, 600 * 1024)
    }
}

final class FlipperPathValidationTests: XCTestCase {

    func testValidPathsPass() {
        XCTAssertNoThrow(try FlipperFileSystem.validate(path: "/ext/subghz/x.sub"))
        XCTAssertNoThrow(try FlipperFileSystem.validate(path: "/int/foo"))
    }

    func testPathOutsideRootsRejected() {
        XCTAssertThrowsError(try FlipperFileSystem.validate(path: "/etc/passwd"))
    }

    func testTraversalRejected() {
        XCTAssertThrowsError(try FlipperFileSystem.validate(path: "/ext/../int/secret"))
    }

    func testControlCharactersRejected() {
        // Newline would let a single CLI line smuggle a second command (Android H1).
        XCTAssertThrowsError(try FlipperFileSystem.validate(path: "/ext/a\nstorage remove /ext/b"))
    }
}
