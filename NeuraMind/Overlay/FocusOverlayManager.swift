import AppKit
import Observation

/// Manages per-display overlay windows using layer-0 window ordering.
/// The overlay sits behind the focused window so the active window naturally occludes it.
@MainActor
final class FocusOverlayManager {
    private var overlays: [CGDirectDisplayID: (window: FocusOverlayWindow, contentView: FocusOverlayContentView)] = [:]
    private let overlayState: OverlayState
    private let poller: FocusOverlayPoller
    private let notchEars = NotchEarOverlay()
    private var lastSnapshots: [FocusWindowSnapshot] = []
    private var overlaysVisible = false
    private var wasEnabled = false

    init(overlayState: OverlayState, poller: FocusOverlayPoller) {
        self.overlayState = overlayState
        self.poller = poller
        setupDisplayNotifications()
        setupSpaceNotifications()
    }

    func createOverlays() {
        removeAllOverlays()
        let screens = NSScreen.screens
        // Overlay windows created per-display
        for screen in screens {
            createOverlay(for: screen)
        }
        if overlayState.isEnabled {
            wasEnabled = false
        }
    }

    func removeAllOverlays() {
        for (_, entry) in overlays {
            entry.contentView.teardown()
            entry.window.close()
        }
        overlays.removeAll()
        notchEars.teardown()
        overlaysVisible = false
    }

    func update() {
        // Handle disable
        if !overlayState.isEnabled {
            if wasEnabled {
                wasEnabled = false
                for (_, entry) in overlays {
                    entry.contentView.teardown()
                    entry.window.fadeOut()
                }
                notchEars.hide()
                overlaysVisible = false
                lastSnapshots = []
            }
            return
        }

        // FAST PATH: When NeuraMind is frontmost the poller freezes snapshots
        // (they stay non-empty from the last real app). The overlay just keeps its
        // current position -- no hiding, no showing, no flash.
        // Only hide if snapshots are truly empty (e.g. overlay just enabled, no app yet).
        let snapshots = poller.focusedSnapshots
        if snapshots.isEmpty {
            if overlaysVisible {
                for (_, entry) in overlays { entry.window.orderOut(nil) }
                overlaysVisible = false
            }
            notchEars.hide()
            lastSnapshots = []
            return
        }

        // If snapshots haven't changed (NeuraMind frontmost = frozen snapshots),
        // skip expensive window reordering but still push effects so slider
        // changes (blur, tint, grain) are applied in real time.
        if snapshots == lastSnapshots && overlaysVisible {
            for (_, entry) in overlays {
                entry.contentView.updateEffects(state: overlayState)
            }
            notchEars.updateEffects(state: overlayState)
            return
        }

        // Handle enable transition
        if !wasEnabled {
            wasEnabled = true
            for (_, entry) in overlays {
                entry.window.fadeIn()
            }
            overlaysVisible = true
        }

        // Reconcile displays
        let currentDisplayIDs = Set(overlays.keys)
        let activeScreens = NSScreen.screens
        let activeDisplayIDs = Set(activeScreens.map { $0.displayID })

        for displayID in currentDisplayIDs.subtracting(activeDisplayIDs) {
            if let entry = overlays.removeValue(forKey: displayID) {
                entry.contentView.teardown()
                entry.window.close()
            }
        }

        for screen in activeScreens where !currentDisplayIDs.contains(screen.displayID) {
            createOverlay(for: screen)
        }

        // Push effects
        for (_, entry) in overlays {
            entry.contentView.updateEffects(state: overlayState)
        }
        notchEars.updateEffects(state: overlayState)

        // Check fullscreen: hide main overlays, show notch ears instead
        let fsScreen = fullscreenScreen(from: snapshots)
        if let fsScreen {
            if overlaysVisible {
                for (_, entry) in overlays { entry.window.orderOut(nil) }
                overlaysVisible = false
            }
            notchEars.show(on: fsScreen, state: overlayState)
            return
        }

        // Not fullscreen: main overlays cover ears, hide ear windows
        notchEars.hide()

        let focusChanged = snapshots != lastSnapshots

        if focusChanged || !overlaysVisible {
            lastSnapshots = snapshots

            for (displayID, entry) in overlays {
                let frames = snapshots
                    .filter { $0.displayID == displayID }
                    .map { $0.frame }
                entry.contentView.applyMask(focusedFrames: frames)
                entry.window.orderFrontRegardless()
            }
            overlaysVisible = true
        } else {
            for (_, entry) in overlays where !entry.window.isVisible {
                entry.window.orderFrontRegardless()
            }
        }
    }

    private func fullscreenScreen(from snapshots: [FocusWindowSnapshot]) -> NSScreen? {
        guard let snapshot = snapshots.first else { return nil }
        for screen in NSScreen.screens where screen.displayID == snapshot.displayID {
            let sf = screen.frame
            let notchInset = screen.safeAreaInsets.top
            let frame = snapshot.frame
            let widthMatches = abs(frame.width - sf.width) < 2
            let xMatches = abs(frame.origin.x - sf.origin.x) < 2
            let fullHeightMatches = abs(frame.height - sf.height) < 2
            let belowNotchMatches = notchInset > 0 && abs(frame.height - (sf.height - notchInset)) < 2
            let yMatches = abs(frame.origin.y - sf.origin.y) < 2
                || (notchInset > 0 && abs(frame.origin.y - (sf.origin.y + notchInset)) < 2)
            if widthMatches && xMatches && yMatches && (fullHeightMatches || belowNotchMatches) {
                return screen
            }
        }
        return nil
    }

    private func createOverlay(for screen: NSScreen) {
        let window = FocusOverlayWindow(screen: screen)
        let contentView = FocusOverlayContentView(frame: screen.frame, screen: screen)
        window.contentView = contentView
        overlays[screen.displayID] = (window, contentView)
    }

    private func setupDisplayNotifications() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.createOverlays()
                self?.update()
            }
        }
    }

    private func setupSpaceNotifications() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.lastSnapshots = []
                self?.update()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    MainActor.assumeIsolated {
                        self?.lastSnapshots = []
                        self?.update()
                    }
                }
            }
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return deviceDescription[key] as? CGDirectDisplayID ?? CGMainDisplayID()
    }
}
