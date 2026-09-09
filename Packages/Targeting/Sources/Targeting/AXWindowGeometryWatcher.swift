import ApplicationServices
import Foundation

/// Observes another process’s focused/main window for move, resize, and
/// window-focus changes. Event-driven — no polling.
///
/// Main-thread only: the AX observer is attached to the main run loop, and
/// `onChanging` is invoked there synchronously.
public final class AXWindowGeometryWatcher {
    public var onChanging: (() -> Void)?

    private var observer: AXObserver?
    private var appElement: AXUIElement?
    private var windowElement: AXUIElement?

    private static let windowNotifications: [CFString] = [
        kAXMovedNotification as CFString,
        kAXResizedNotification as CFString,
        kAXUIElementDestroyedNotification as CFString,
        kAXWindowMiniaturizedNotification as CFString,
        kAXWindowDeminiaturizedNotification as CFString,
    ]

    private static let appNotifications: [CFString] = [
        kAXFocusedWindowChangedNotification as CFString,
        kAXMainWindowChangedNotification as CFString,
        kAXApplicationHiddenNotification as CFString,
        kAXApplicationShownNotification as CFString,
    ]

    public init() {}

    deinit {
        let observer = observer
        let appElement = appElement
        let windowElement = windowElement
        if Thread.isMainThread {
            Self.teardown(observer: observer, app: appElement, window: windowElement)
        } else {
            DispatchQueue.main.async {
                Self.teardown(observer: observer, app: appElement, window: windowElement)
            }
        }
    }

    public func watch(pid: pid_t) {
        stop()
        let app = AXUIElementCreateApplication(pid)
        appElement = app

        var created: AXObserver?
        let status = AXObserverCreate(pid, { _, _, notification, refcon in
            guard let refcon else { return }
            Unmanaged<AXWindowGeometryWatcher>.fromOpaque(refcon)
                .takeUnretainedValue()
                .handle(notification)
        }, &created)
        guard status == .success, let created else {
            AppLog.log(.target, "AXObserverCreate failed pid=\(pid) err=\(status.rawValue)")
            appElement = nil
            return
        }
        observer = created
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)

        addNotifications(Self.appNotifications, to: app, observer: created)
        rebindWindow()
    }

    public func stop() {
        let observer = observer
        let app = appElement
        let window = windowElement
        self.observer = nil
        self.appElement = nil
        self.windowElement = nil
        Self.teardown(observer: observer, app: app, window: window)
    }

    private func handle(_ notification: CFString) {
        if CFEqual(notification, kAXFocusedWindowChangedNotification as CFString)
            || CFEqual(notification, kAXMainWindowChangedNotification as CFString) {
            rebindWindow()
        }
        onChanging?()
    }

    private func rebindWindow() {
        guard let observer, let appElement else { return }
        if let windowElement {
            Self.removeNotifications(Self.windowNotifications, from: windowElement, observer: observer)
        }
        windowElement = copyPreferredWindow(appElement)
        if let windowElement {
            addNotifications(Self.windowNotifications, to: windowElement, observer: observer)
        }
    }

    private func addNotifications(_ names: [CFString], to element: AXUIElement, observer: AXObserver) {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in names {
            let error = AXObserverAddNotification(observer, element, name, refcon)
            if error != .success, error != .notificationAlreadyRegistered {
                AppLog.log(.target, "AX observe failed \(name as String) err=\(error.rawValue)")
            }
        }
    }

    private static func removeNotifications(
        _ names: [CFString],
        from element: AXUIElement,
        observer: AXObserver
    ) {
        for name in names {
            AXObserverRemoveNotification(observer, element, name)
        }
    }

    private static func teardown(observer: AXObserver?, app: AXUIElement?, window: AXUIElement?) {
        guard let observer else { return }
        if let app {
            removeNotifications(appNotifications, from: app, observer: observer)
        }
        if let window {
            removeNotifications(windowNotifications, from: window, observer: observer)
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    private func copyPreferredWindow(_ app: AXUIElement) -> AXUIElement? {
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] as [CFString] {
            var ref: AnyObject?
            if AXUIElementCopyAttributeValue(app, attribute, &ref) == .success, let ref {
                return (ref as! AXUIElement)
            }
        }
        return nil
    }
}
