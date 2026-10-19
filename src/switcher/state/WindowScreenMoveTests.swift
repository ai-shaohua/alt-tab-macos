import XCTest

/// Pins the geometry and the step list for moving a window onto another screen. No AX, no window.
///
/// Groups: A coordinates · B landing position · C steps.
final class WindowScreenMoveTests: XCTestCase {
    private func frame(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> WindowScreenMove.Frame {
        WindowScreenMove.Frame(origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height))
    }

    // MARK: - A. Coordinates

    func testQuartzFrameFlipsYAgainstThePrimaryTop() {
        let quartz = WindowScreenMove.quartzFrame(cocoa: CGRect(x: 1920, y: 0, width: 800, height: 600), primaryMaxY: 1080)
        XCTAssertEqual(quartz, frame(1920, 480, 800, 600))
    }

    func testCocoaOriginIsTheInverseOfTheQuartzTopLeft() {
        let cocoa = WindowScreenMove.cocoaOrigin(quartzTopLeft: CGPoint(x: 1920, y: 480), windowHeight: 600, primaryMaxY: 1080)
        XCTAssertEqual(cocoa, CGPoint(x: 1920, y: 0))
    }

    // MARK: - B. Landing position

    func testRelativePositionIsKeptOnADifferentlySizedScreen() {
        let landed = WindowScreenMove.position(windowOrigin: CGPoint(x: 250, y: 125), windowSize: CGSize(width: 100, height: 50),
            from: frame(0, 0, 1000, 500), to: frame(2000, 0, 2000, 1000))
        XCTAssertEqual(landed, CGPoint(x: 2500, y: 250))
    }

    func testAWindowWiderThanTheTargetPinsToItsTopLeft() {
        let landed = WindowScreenMove.position(windowOrigin: CGPoint(x: 250, y: 125), windowSize: CGSize(width: 3000, height: 50),
            from: frame(0, 0, 1000, 500), to: frame(2000, 0, 2000, 1000))
        XCTAssertEqual(landed.x, 2000)
        XCTAssertEqual(landed.y, 250)
    }

    func testNoSourceFramePinsToTheTargetOrigin() {
        let landed = WindowScreenMove.position(windowOrigin: nil, windowSize: CGSize(width: 10, height: 10),
            from: nil, to: frame(5, 6, 100, 100))
        XCTAssertEqual(landed, CGPoint(x: 5, y: 6))
    }

    // MARK: - C. Steps

    func testAnOrdinaryWindowIsOnlyRepositioned() {
        XCTAssertEqual(WindowScreenMove.steps(isFullscreen: false, isMinimized: false, position: CGPoint(x: 1, y: 2)),
            [.setPosition(CGPoint(x: 1, y: 2))])
    }

    func testAMinimizedWindowIsRestoredBeforeTheMove() {
        XCTAssertEqual(WindowScreenMove.steps(isFullscreen: false, isMinimized: true, position: .zero),
            [.deminiaturize, .setPosition(.zero)])
    }

    func testAFullscreenWindowLeavesMovesAndReenters() {
        XCTAssertEqual(WindowScreenMove.steps(isFullscreen: true, isMinimized: false, position: .zero),
            [.exitFullscreen, .setPosition(.zero), .enterFullscreen])
    }

    func testAMinimizedFullscreenWindowRestoresThenLeaves() {
        XCTAssertEqual(WindowScreenMove.steps(isFullscreen: true, isMinimized: true, position: .zero),
            [.deminiaturize, .exitFullscreen, .setPosition(.zero), .enterFullscreen])
    }

    func testAnimatedStepsWaitAndTheLastFullscreenEnterDoesNot() {
        XCTAssertEqual(WindowScreenMove.pauseAfter(.deminiaturize), 1)
        XCTAssertEqual(WindowScreenMove.pauseAfter(.exitFullscreen), 1)
        XCTAssertEqual(WindowScreenMove.pauseAfter(.setPosition(.zero)), 1)
        XCTAssertEqual(WindowScreenMove.pauseAfter(.enterFullscreen), 0)
    }
}
