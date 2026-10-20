import Cocoa

class ScreensEvents {
    private static let screenChangeThrottler = Throttler(delayInMs: 200)

    static func observe() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleEvent), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private static func handleEvent(_ notification: Notification) {
        // screen notifications often arrive in groups (e.g. 2 in a row in a short time)
        screenChangeThrottler.throttleOrProceed {
            Logger.debug { notification.name.rawValue }
            Self.rebind()
            // a screen added or removed, or screen resolution change can mess up layout; we reset components
            App.resetPreferencesDependentComponents()
            // a screen added or removed can shuffle windows around Spaces; we refresh them
            App.refreshOpenUiAfterExternalEvent(Windows.list)
            Logger.info { "screens:\(NSScreen.screens.map { ($0.cachedUuid() ?? "nil" as CFString, $0.frame) })" }
            Logger.info { "currentSpace:\(Spaces.currentSpaceIndex) (id:\(Spaces.currentSpaceId)) spaces:\(Spaces.screenSpacesMap)" }
            // The notification often arrives while `NSScreen.screens` is still empty. One later pass
            // picks up the displays once they are back.
            guard NSScreen.screens.isEmpty else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(400)) {
                guard !NSScreen.screens.isEmpty else { return }
                Self.rebind()
                App.refreshOpenUiAfterExternalEvent(Windows.list)
            }
        }
    }

    private static func rebind() {
        Spaces.refresh()
        Screens.refresh()
        Windows.list.forEach { $0.updateScreenId() }
    }
}
