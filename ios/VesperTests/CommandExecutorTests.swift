import XCTest
@testable import Vesper

/// Tests the pure approval decision — the fix for the retired Android build's H3
/// (auto-approve-high silencing irreversible actions).
final class CommandExecutorApprovalTests: XCTestCase {

    func testLowNeverNeedsApproval() {
        XCTAssertFalse(CommandExecutor.requiresApproval(
            action: .readFile, level: .low, autoApproveMedium: false, autoApproveHigh: false))
    }

    func testMediumNeedsApprovalUnlessAutoApproved() {
        XCTAssertTrue(CommandExecutor.requiresApproval(
            action: .writeFile, level: .medium, autoApproveMedium: false, autoApproveHigh: false))
        XCTAssertFalse(CommandExecutor.requiresApproval(
            action: .writeFile, level: .medium, autoApproveMedium: true, autoApproveHigh: false))
    }

    func testHighReversibleRespectsAutoApprove() {
        // `move` is high but reversible; auto-approve-high covers it.
        XCTAssertFalse(CommandExecutor.requiresApproval(
            action: .move, level: .high, autoApproveMedium: false, autoApproveHigh: true))
    }

    func testIrreversibleAlwaysNeedsApprovalEvenWithAutoApprove() {
        for action in [CommandAction.delete, .badusbExecute, .subghzTransmit, .pushArtifact, .installFaphubApp] {
            XCTAssertTrue(
                CommandExecutor.requiresApproval(action: action, level: .high,
                                                 autoApproveMedium: true, autoApproveHigh: true),
                "\(action) must never be auto-approved")
        }
    }

    func testBlockedAlwaysNeedsApproval() {
        XCTAssertTrue(CommandExecutor.requiresApproval(
            action: .readFile, level: .blocked, autoApproveMedium: true, autoApproveHigh: true))
    }
}

final class DiffServiceTests: XCTestCase {

    func testUnifiedDiffMarksAddedAndRemoved() {
        let diff = DiffService().unifiedDiff(old: "a\nb\nc", new: "a\nB\nc")
        XCTAssertTrue(diff.contains("- b"))
        XCTAssertTrue(diff.contains("+ B"))
    }

    func testIdenticalContentHasNoChanges() {
        XCTAssertEqual(DiffService().unifiedDiff(old: "same\nlines", new: "same\nlines"), "")
    }
}
