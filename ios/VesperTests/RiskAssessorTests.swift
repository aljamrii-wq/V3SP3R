import XCTest
@testable import Vesper

final class RiskAssessorTests: XCTestCase {

    private let assessor = RiskAssessor()

    private func command(_ action: CommandAction, args: CommandArgs = CommandArgs()) -> ExecuteCommand {
        ExecuteCommand(action: action, args: args)
    }

    func testReadOnlyActionsAreLow() {
        XCTAssertEqual(assessor.assess(command(.listDirectory)).level, .low)
        XCTAssertEqual(assessor.assess(command(.readFile)).level, .low)
        XCTAssertEqual(assessor.assess(command(.getDeviceInfo)).level, .low)
    }

    func testWriteFileIsMediumWithDiff() {
        let assessment = assessor.assess(command(.writeFile))
        XCTAssertEqual(assessment.level, .medium)
        XCTAssertTrue(assessment.requiresDiff)
    }

    func testDeleteIsHighAndHoldToConfirm() {
        let assessment = assessor.assess(command(.delete))
        XCTAssertEqual(assessment.level, .high)
        XCTAssertTrue(assessment.requiresHoldToConfirm)
    }

    func testProtectedPathIsBlockedWithoutUnlock() {
        var args = CommandArgs(); args.path = "/int/rfid"
        XCTAssertEqual(assessor.assess(command(.readFile, args: args)).level, .blocked)
    }

    func testProtectedPathAllowedWithActiveUnlock() {
        var args = CommandArgs(); args.path = "/int/rfid"
        let unlock = ProtectedUnlock(pathPrefix: "/int", expiresAt: Date().addingTimeInterval(600))
        // Not blocked; falls through to per-action classification (read = low).
        XCTAssertEqual(assessor.assess(command(.readFile, args: args), unlocks: [unlock]).level, .low)
    }

    func testTraversalIntoProtectedPathIsBlocked() {
        var args = CommandArgs(); args.path = "/ext/../int/secret"
        XCTAssertEqual(assessor.assess(command(.readFile, args: args)).level, .blocked)
    }

    // The key fix over the retired Android build: full-command CLI classification.

    func testChainedDestructiveCliIsNotLow() {
        var args = CommandArgs(); args.command = "storage list /ext; storage format /ext"
        XCTAssertEqual(assessor.assess(command(.executeCli, args: args)).level, .blocked)
    }

    func testRemoveRecursiveCliIsHigh() {
        var args = CommandArgs(); args.command = "storage remove_recursive /ext/foo"
        XCTAssertEqual(assessor.assess(command(.executeCli, args: args)).level, .high)
    }

    func testReadOnlyCliIsLow() {
        var args = CommandArgs(); args.command = "storage list /ext"
        XCTAssertEqual(assessor.assess(command(.executeCli, args: args)).level, .low)
    }

    func testChainedReadOnlyCliEscalatesToMedium() {
        var args = CommandArgs(); args.command = "storage list /ext && device_info"
        XCTAssertEqual(assessor.assess(command(.executeCli, args: args)).level, .medium)
    }

    // Operation modes are enforced (Android H4).

    func testStealthModeBlocksTransmit() {
        var args = CommandArgs(); args.signalFile = "/ext/subghz/x.sub"
        XCTAssertEqual(assessor.assess(command(.subghzTransmit, args: args), mode: .stealth).level, .blocked)
    }

    func testReconModeBlocksEmulation() {
        XCTAssertEqual(assessor.assess(command(.nfcEmulate), mode: .recon).level, .blocked)
    }

    func testStandardModeAllowsTransmitAsHigh() {
        var args = CommandArgs(); args.signalFile = "/ext/subghz/x.sub"
        XCTAssertEqual(assessor.assess(command(.subghzTransmit, args: args), mode: .standard).level, .high)
    }
}
