import AppKit
import SwiftUI

// A window-scoped monitor preserves normal vertical scrolling in SwiftUI List
// while recognizing the horizontal phase of a precise trackpad gesture.
struct CategorySwipeGesture: NSViewRepresentable {
    var enabled: Bool
    var onSwipe: (Int) -> Void

    func makeNSView(context: Context) -> SwipeMonitorView {
        let view = SwipeMonitorView()
        view.enabled = enabled
        view.onSwipe = onSwipe
        view.startMonitoring()
        return view
    }

    func updateNSView(_ view: SwipeMonitorView, context: Context) {
        view.enabled = enabled
        view.onSwipe = onSwipe
        if !enabled { view.reset() }
    }

    static func dismantleNSView(_ view: SwipeMonitorView, coordinator: ()) {
        view.stopMonitoring()
    }
}

final class SwipeMonitorView: NSView {
    var enabled = true
    var onSwipe: ((Int) -> Void)?
    private var monitor: Any?
    private var totalX: CGFloat = 0
    private var totalY: CGFloat = 0
    private var vertical = false
    private var switched = false
    private var horizontal = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func reset() {
        totalX = 0; totalY = 0
        vertical = false; switched = false; horizontal = false
    }

    func startMonitoring() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.enabled, let window = self.window,
                  event.window === window, window.isKeyWindow, window.attachedSheet == nil,
                  event.hasPreciseScrollingDeltas, !event.phase.isEmpty else { return event }
            // Momentum must never trigger a second category change.
            guard event.momentumPhase.isEmpty else { return event }
            if event.phase.contains(.began) || event.phase.contains(.mayBegin) { self.reset() }
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                let consumed = self.horizontal
                self.reset()
                return consumed ? nil : event
            }
            self.totalX += event.scrollingDeltaX
            self.totalY += event.scrollingDeltaY
            if !self.horizontal && abs(self.totalY) > 12 && abs(self.totalY) > abs(self.totalX) * 1.25 {
                self.vertical = true
            }
            guard !self.vertical else { return event }
            if abs(self.totalX) > 12 && abs(self.totalX) > abs(self.totalY) * 1.5 {
                self.horizontal = true
            }
            if self.horizontal && !self.switched && abs(self.totalX) >= 60 {
                self.switched = true
                self.onSwipe?(self.totalX < 0 ? 1 : -1)
            }
            return self.horizontal ? nil : event
        }
    }

    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        reset()
    }

    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}
