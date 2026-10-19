import Foundation

/// Where a window lands when it is dropped on another screen, and the Accessibility steps that get
/// it there. Geometry only: the shell (`Window.moveToScreen`) turns the steps into AX writes.
enum WindowScreenMove {
    /// AX ignores a position write, and ignores entering fullscreen, while a fullscreen-exit or
    /// un-minimize animation is in progress. `Window.minDemin` waits this long before minimizing a
    /// window that is leaving fullscreen; the same gap sits between the steps here.
    static let animationDelay: TimeInterval = 1

    struct Frame: Equatable {
        var origin: CGPoint
        var size: CGSize
    }

    enum Step: Equatable {
        case deminiaturize
        case exitFullscreen
        case setPosition(CGPoint)
        case enterFullscreen
    }

    /// AX position is the window's top-left in Quartz coordinates (origin at the top-left of the
    /// primary display, y grows down). `primaryMaxY` is the Cocoa max-Y of `NSScreen.screens[0]`.
    static func quartzFrame(cocoa: CGRect, primaryMaxY: CGFloat) -> Frame {
        Frame(origin: CGPoint(x: cocoa.minX, y: primaryMaxY - cocoa.maxY), size: cocoa.size)
    }

    static func cocoaOrigin(quartzTopLeft: CGPoint, windowHeight: CGFloat, primaryMaxY: CGFloat) -> CGPoint {
        CGPoint(x: quartzTopLeft.x, y: primaryMaxY - quartzTopLeft.y - windowHeight)
    }

    /// Keeps the window's relative position on the source screen. A window with no source frame, or
    /// one larger than the target, pins to the target's top-left. The result is clamped so the window
    /// stays inside the target.
    static func position(windowOrigin: CGPoint?, windowSize: CGSize, from: Frame?, to: Frame) -> CGPoint {
        let proposed = proposedOrigin(windowOrigin, from, to)
        return CGPoint(
            x: clamp(proposed.x, window: windowSize.width, start: to.origin.x, span: to.size.width),
            y: clamp(proposed.y, window: windowSize.height, start: to.origin.y, span: to.size.height))
    }

    /// A native-fullscreen window occupies its own Space, so a position write does not move that
    /// Space. Leave fullscreen, move the ordinary window onto the target screen, then enter
    /// fullscreen there: the new Space is created on whichever screen holds the window. A minimized
    /// window has no on-screen frame until it is restored.
    static func steps(isFullscreen: Bool, isMinimized: Bool, position: CGPoint) -> [Step] {
        var steps = [Step]()
        if isMinimized { steps.append(.deminiaturize) }
        if isFullscreen { steps.append(.exitFullscreen) }
        steps.append(.setPosition(position))
        if isFullscreen { steps.append(.enterFullscreen) }
        return steps
    }

    static func pauseAfter(_ step: Step) -> TimeInterval {
        switch step {
            case .enterFullscreen: return 0
            case .deminiaturize, .exitFullscreen, .setPosition: return animationDelay
        }
    }

    private static func proposedOrigin(_ windowOrigin: CGPoint?, _ from: Frame?, _ to: Frame) -> CGPoint {
        guard let from, let windowOrigin, from.size.width > 0, from.size.height > 0 else { return to.origin }
        let relativeX = (windowOrigin.x - from.origin.x) / from.size.width
        let relativeY = (windowOrigin.y - from.origin.y) / from.size.height
        return CGPoint(x: to.origin.x + relativeX * to.size.width, y: to.origin.y + relativeY * to.size.height)
    }

    private static func clamp(_ proposed: CGFloat, window: CGFloat, start: CGFloat, span: CGFloat) -> CGFloat {
        guard window < span else { return start }
        return min(max(proposed, start), start + span - window)
    }
}
