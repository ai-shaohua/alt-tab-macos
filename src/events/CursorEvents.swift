import Cocoa
import Carbon.HIToolbox.Events

class CursorEvents {
    private static var eventTap: CFMachPort!
    private static var shouldBeEnabled: Bool!
    private static var mouseDownTarget: AnyObject?
    private static var mouseDownInsideSearchField = false
    private static var searchHintClick = SearchDiscoveryPolicy.Click()
    /// true once the tap has observed a leftMouseDown since the switcher showed (reset per gesture and on
    /// each show). A drag from another app started before the switcher showed, so its down was never seen —
    /// that is how `handleLeftMouseUp` recognizes a drop's up and yields it (see `DragAndDropResolver`).
    private static var sawLeftMouseDown = false
    private static var tileDrag: TileDrag?
    static var deadZoneInitialPosition: CGPoint?
    static var isAllowedToMouseHover = true

    static func toggle(_ enabled: Bool) {
        guard enabled != shouldBeEnabled else { return }
        shouldBeEnabled = enabled
        if !enabled {
            deadZoneInitialPosition = nil
            tileDrag = nil
            Window.pendingScreenMoves.removeAll()
            TilesView.screenColumnChrome.highlight(nil)
        } else {
            sawLeftMouseDown = false // fresh session: a drag in flight when we show has no down we saw
            searchHintClick = SearchDiscoveryPolicy.Click()
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: enabled)
        }
    }

    static func reEnableTapIfNeeded() {
        if CGEvent.reEnableTapIfNeeded(eventTap, wanted: shouldBeEnabled) {
            Logger.warning { "" }
        }
    }

    static func observe() {
        let eventMask = [CGEventType.leftMouseDown, CGEventType.leftMouseUp, CGEventType.leftMouseDragged, CGEventType.rightMouseDown, CGEventType.rightMouseUp, CGEventType.otherMouseDown, CGEventType.otherMouseUp, CGEventType.mouseMoved].reduce(CGEventMask(0), { $0 | (1 << $1.rawValue) })
        eventTap = CGEvent.createTapOrRestart(
            tap: .cgSessionEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: handleEvent,
            // we run on main-thread directly since all we do is check NSEvent and UI coordinates, which we must do on main-thread
            runLoop: CFRunLoopGetMain())
        if eventTap != nil {
            toggle(false)
        }
    }

    private static let handleEvent: CGEventTapCallBack = { _, type, cgEvent, _ in
        switch type {
            case .leftMouseDown: return handleLeftMouseDown(cgEvent)
            case .leftMouseUp: return handleLeftMouseUp(cgEvent)
            case .leftMouseDragged: return handleLeftMouseDragged(cgEvent)
            case .rightMouseDown: return handleRightMouseDown(cgEvent)
            case .rightMouseUp: return handleRightMouseUp(cgEvent)
            case .otherMouseDown: return handleOtherMouseDown(cgEvent)
            case .otherMouseUp: return handleOtherMouseUp(cgEvent)
            case .mouseMoved: return handleMouseMoved(cgEvent)
            case .tapDisabledByUserInput, .tapDisabledByTimeout:
                if shouldBeEnabled { CGEvent.tapEnable(tap: eventTap!, enable: true) }
                return Unmanaged.passUnretained(cgEvent)
            default: return Unmanaged.passUnretained(cgEvent)
        }
    }

    private static func handleLeftMouseDown(_ cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        sawLeftMouseDown = true // this gesture's down is ours; its up is a click, not a foreign drop
        if searchHintClick.begin(inside: SearchDiscoveryHint.shared.containsMouseLocation) {
            mouseDownTarget = nil
            mouseDownInsideSearchField = false
            return Unmanaged.passUnretained(cgEvent)
        }
        if TilesView.hasMarkedText() || ContextMenuEvents.isMenuOpen { return Unmanaged.passUnretained(cgEvent) }
        if isPointerInsideSearchField() {
            mouseDownInsideSearchField = true
            return Unmanaged.passUnretained(cgEvent)
        }
        mouseDownInsideSearchField = false
        guard isPointerInsideUi() else { tileDrag = nil; return nil }
        mouseDownTarget = (findButtonUnderPointer() ?? findTileViewUnderPointer()) as AnyObject?
        tileDrag = nil
        if let tile = mouseDownTarget as? TileView { armTileDrag(tile) }
        return nil
    }

    private static func handleLeftMouseDragged(_ cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        guard tileDrag != nil else { return Unmanaged.passUnretained(cgEvent) }
        updateTileDrag()
        return nil
    }

    private static func handleLeftMouseUp(_ cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        let sawDown = sawLeftMouseDown
        sawLeftMouseDown = false
        if searchHintClick.end(inside: SearchDiscoveryHint.shared.containsMouseLocation) {
            mouseDownTarget = nil
            return Unmanaged.passUnretained(cgEvent)
        }
        // a drag from another app ends with a leftMouseUp whose matching down we never saw (it happened
        // before the switcher showed). Don't swallow it, or the drop never concludes and the file stays
        // stuck on the cursor — whether released on a tile, the padding around the tiles, or outside the
        // panel. Let AppKit / the source app conclude the drop (see DragAndDropResolver).
        if DragAndDropResolver.passesThroughMouseUp(mouseDownWasSeen: sawDown) {
            return Unmanaged.passUnretained(cgEvent)
        }
        if TilesView.hasMarkedText() || ContextMenuEvents.isMenuOpen { return Unmanaged.passUnretained(cgEvent) }
        if mouseDownInsideSearchField || isPointerInsideSearchField() {
            mouseDownInsideSearchField = false
            return Unmanaged.passUnretained(cgEvent)
        }
        if tileDrag != nil {
            let wasDragging = tileDrag?.dragging == true
            finishTileDrag()
            if wasDragging {
                mouseDownTarget = nil
                return nil
            }
        }
        guard isPointerInsideUi() else {
            if mouseDownTarget == nil { App.hideUi() }
            mouseDownTarget = nil
            return nil
        }
        let downTarget = mouseDownTarget
        mouseDownTarget = nil
        if let button = findButtonUnderPointer(), button === downTarget {
            button.onClick()
            return nil
        }
        if let target = findTileViewUnderPointer(), target === downTarget {
            target.mouseUpCallback()
            return nil
        }
        return nil
    }

    private static func handleRightMouseDown(_ cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        if ContextMenuEvents.isMenuOpen || isPointerInsideUi() { return Unmanaged.passUnretained(cgEvent) }
        return nil
    }

    private static func handleRightMouseUp(_ cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        if ContextMenuEvents.isMenuOpen || isPointerInsideUi() { return Unmanaged.passUnretained(cgEvent) }
        return nil
    }

    /// must stay symmetric with `handleOtherMouseUp`: we always swallow the up (it's our close-window click),
    /// so letting the down through would leave WindowServer thinking the button is still held
    private static func handleOtherMouseDown(_ cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        if ContextMenuEvents.isMenuOpen { return Unmanaged.passUnretained(cgEvent) }
        return nil
    }

    private static func handleOtherMouseUp(_ cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        if ContextMenuEvents.isMenuOpen { return Unmanaged.passUnretained(cgEvent) }
        if isPointerInsideUi(),
           cgEvent.getIntegerValueField(.mouseEventButtonNumber) == 2,
           let target = findTileViewUnderPointer(),
           let window = target.window_ {
            window.isWindowlessApp ? window.application.quit() : window.close()
        }
        return nil
    }

    private static func handleMouseMoved(_ cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        if isAllowedToReactToPointerMovement(cgEvent.location) {
            TilesView.thumbnailOverView.updateHover()
        }
        return Unmanaged.passUnretained(cgEvent)
    }

    static func resetDeadzone() {
        deadZoneInitialPosition = nil
        isAllowedToMouseHover = false
    }

    static func isAllowedToReactToPointerMovement(_ location: CGPoint) -> Bool {
        updateDeadzoneSituation(location)
        return isAllowedToMouseHover
    }

    private struct TileDrag {
        var tile: TileView
        var window: Window
        var sourceColumn: Int
        var down: CGPoint
        var origin: CGPoint
        var dragging: Bool
    }

    private static func armTileDrag(_ tile: TileView) {
        guard !TilesView.screenColumnFrames.isEmpty, let window = tile.window_ else { return }
        let down = pointerInDocument()
        let center = CGPoint(x: tile.frame.midX, y: tile.frame.midY)
        let source = ScreenColumnLayout.dropIndex(at: center, columns: TilesView.screenColumnFrames) ?? 0
        tileDrag = TileDrag(tile: tile, window: window, sourceColumn: source, down: down, origin: tile.frame.origin, dragging: false)
    }

    private static func updateTileDrag() {
        guard var session = tileDrag else { return }
        let current = pointerInDocument()
        guard session.dragging || ScreenColumnLayout.crossedDragThreshold(from: session.down, to: current) else { return }
        session.dragging = true
        tileDrag = session
        session.tile.frame.origin = CGPoint(x: session.origin.x + current.x - session.down.x, y: session.origin.y + current.y - session.down.y)
        session.tile.superview?.addSubview(session.tile, positioned: .below, relativeTo: TilesView.thumbnailOverView)
        TilesView.screenColumnChrome.highlight(TilesView.screenColumn(at: current))
        TilesView.thumbnailOverView.hideWindowControls()
    }

    private static func finishTileDrag() {
        guard let session = tileDrag else { return }
        tileDrag = nil
        TilesView.screenColumnChrome.highlight(nil)
        guard session.dragging else { return }
        let destination = TilesView.screenColumn(at: pointerInDocument())
        if let destination, destination != session.sourceColumn, let screen = TilesView.screen(forColumn: destination) {
            session.window.moveToScreen(screen)
        } else if SwitcherSession.isActive {
            App.refreshUi(true)
        }
    }

    private static func pointerInDocument() -> NSPoint {
        TilesView.thumbnailOverView.convert(pointerLocationInWindow(), from: nil)
    }

    private static func pointerLocationInWindow() -> NSPoint {
        TilesPanel.shared.mouseLocationOutsideOfEventStream
    }

    private static func isPointerInsideUi() -> Bool {
        TilesPanel.shared.contentLayoutRect.contains(pointerLocationInWindow())
    }

    private static func isPointerInsideSearchField() -> Bool {
        let searchField = TilesView.searchField
        if searchField.isHidden { return false }
        let point = searchField.convert(pointerLocationInWindow(), from: nil)
        return searchField.bounds.contains(point)
    }

    private static func pointerInOverlay() -> (TileOverView, NSPoint) {
        let overlay = TilesView.thumbnailOverView
        return (overlay, overlay.convert(pointerLocationInWindow(), from: nil))
    }

    private static func findButtonUnderPointer() -> TrafficLightButton? {
        let (overlay, point) = pointerInOverlay()
        return overlay.findButton(point)
    }

    private static func findTileViewUnderPointer() -> TileView? {
        let (overlay, point) = pointerInOverlay()
        return overlay.findTarget(point)
    }

    /// when using the trackpad, the user may swipe with a slight mistake. This will create a small cursor movement
    /// we ignore those, as they are not intended. Intended movements will be larger and not ignored
    private static func updateDeadzoneSituation(_ location: CGPoint) {
        guard let deadZoneInitialPosition else {
            deadZoneInitialPosition = location
            isAllowedToMouseHover = false
            return
        }
        let deltaX = location.x - deadZoneInitialPosition.x
        let deltaY = location.y - deadZoneInitialPosition.y
        if hypot(deltaX, deltaY) > 25 { isAllowedToMouseHover = true }
    }
}
