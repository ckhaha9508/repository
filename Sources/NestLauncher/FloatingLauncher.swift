import AppKit

private final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class FloatingLauncherController {
    private let panel: NSPanel
    private var screenObserver: NSObjectProtocol?

    init(onToggle: @escaping () -> Void, onShow: @escaping () -> Void,
         onHide: @escaping () -> Void, onSettings: @escaping () -> Void) {
        let size = NSSize(width: 56, height: 96)
        panel = LauncherPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.title = L10n.tr("Nest Launcher 悬浮图标")
        panel.identifier = NSUserInterfaceItemIdentifier("floating-launcher")
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.isReleasedWhenClosed = false
        let icon = FloatingLauncherIcon(frame: NSRect(origin: .zero, size: size))
        icon.autoresizingMask = [.width, .height]
        icon.onToggle = onToggle
        icon.onShow = onShow
        icon.onHide = onHide
        icon.onSettings = onSettings
        icon.image = NSImage(named: NSImage.Name("NestLauncher")) ?? NSApp.applicationIconImage
        icon.toolTip = L10n.tr("点击显示或隐藏 Nest Launcher · 拖动调整位置 · 右键退出")
        icon.setAccessibilityRole(.button)
        icon.setAccessibilityElement(true)
        icon.setAccessibilityLabel(L10n.tr("显示或隐藏 Nest Launcher"))
        panel.contentView = icon

        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let saved = UserDefaults.standard.array(forKey: "floatingLauncherOrigin") as? [Double]
        let origin = saved?.count == 2
            ? NSPoint(x: saved![0], y: saved![1])
            : NSPoint(x: visible.maxX - size.width, y: visible.midY - size.height / 2)
        panel.setFrameOrigin(origin)
        FloatingLauncherIcon.keepOnScreen(panel)
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            FloatingLauncherIcon.keepOnScreen(self.panel)
        }
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    func show() { panel.orderFrontRegardless() }
    func hide() { panel.orderOut(nil) }
    func updateLocalizedText() {
        panel.title = L10n.tr("Nest Launcher 悬浮图标")
        panel.contentView?.toolTip = L10n.tr("点击显示或隐藏 Nest Launcher · 拖动调整位置 · 右键退出")
        panel.contentView?.setAccessibilityLabel(L10n.tr("显示或隐藏 Nest Launcher"))
    }
}

private final class FloatingLauncherIcon: NSView {
    var image: NSImage?
    private enum Edge: Int { case left, right, bottom, top }
    private var edge: Edge = .right
    var onToggle: (() -> Void)?
    var onShow: (() -> Void)?
    var onHide: (() -> Void)?
    var onSettings: (() -> Void)?
    private var startMouse = NSPoint.zero
    private var startOrigin = NSPoint.zero
    private var didDrag = false
    private var isExpanded = false
    private var reveal: CGFloat = 0
    private var hoverTracking: NSTrackingArea?
    private var animationTimer: Timer?

    deinit { animationTimer?.invalidate() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        var hoverRect = bounds
        if !isExpanded {
            switch edge {
            case .right: hoverRect = NSRect(x: bounds.midX, y: 24, width: bounds.width / 2, height: 48)
            case .left: hoverRect = NSRect(x: 0, y: 24, width: bounds.width / 2, height: 48)
            case .top: hoverRect = NSRect(x: 24, y: bounds.midY, width: 48, height: bounds.height / 2)
            case .bottom: hoverRect = NSRect(x: 24, y: 0, width: 48, height: bounds.height / 2)
            }
        }
        let tracking = NSTrackingArea(rect: hoverRect, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(tracking)
        hoverTracking = tracking
    }

    override func mouseEntered(with event: NSEvent) { setExpanded(true) }

    override func mouseExited(with event: NSEvent) {
        if !didDrag { setExpanded(false) }
    }

    private func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else { return }
        isExpanded = expanded
        updateTrackingAreas()
        animationTimer?.invalidate()
        let start = reveal
        let target: CGFloat = expanded ? 1 : 0
        let started = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let progress = min(1, (ProcessInfo.processInfo.systemUptime - started) / 0.24)
            let eased = progress * progress * (3 - 2 * progress)
            self.reveal = start + (target - start) * CGFloat(eased)
            self.needsDisplay = true
            if progress >= 1 { timer.invalidate(); self.animationTimer = nil }
        }
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        // Slide the drawing under the screen edge without moving the tracking
        // window, so hover remains stable throughout the reveal animation.
        let offset = 28 * (1 - reveal)
        switch edge {
        case .right: NSGraphicsContext.current?.cgContext.translateBy(x: offset, y: 0)
        case .left: NSGraphicsContext.current?.cgContext.translateBy(x: -offset, y: 0)
        case .top: NSGraphicsContext.current?.cgContext.translateBy(x: 0, y: offset)
        case .bottom: NSGraphicsContext.current?.cgContext.translateBy(x: 0, y: -offset)
        }
        // Concave shoulders flow into the screen edge, rather than cutting a
        // rounded rectangle flat. Rotate the housing, keeping the icon upright.
        let housing = NSBezierPath()
        housing.move(to: NSPoint(x: 56, y: 0))
        housing.curve(to: NSPoint(x: 28, y: 24), controlPoint1: NSPoint(x: 56, y: 18), controlPoint2: NSPoint(x: 46, y: 24))
        housing.curve(to: NSPoint(x: 4, y: 48), controlPoint1: NSPoint(x: 12, y: 24), controlPoint2: NSPoint(x: 4, y: 34))
        housing.curve(to: NSPoint(x: 28, y: 72), controlPoint1: NSPoint(x: 4, y: 62), controlPoint2: NSPoint(x: 12, y: 72))
        housing.curve(to: NSPoint(x: 56, y: 96), controlPoint1: NSPoint(x: 46, y: 72), controlPoint2: NSPoint(x: 56, y: 78))
        housing.close()
        let transform = AffineTransform(
            m11: 1, m12: 0, m21: 0, m22: 1, tX: 0, tY: 0
        )
        var dockingTransform = transform
        switch edge {
        case .right: break
        case .left: dockingTransform = AffineTransform(m11: -1, m12: 0, m21: 0, m22: 1, tX: 56, tY: 0)
        case .top: dockingTransform = AffineTransform(m11: 0, m12: 1, m21: 1, m22: 0, tX: 0, tY: 0)
        case .bottom: dockingTransform = AffineTransform(m11: 0, m12: -1, m21: 1, m22: 0, tX: 0, tY: 56)
        }
        housing.transform(using: dockingTransform)
        NSColor.black.setFill()
        housing.fill()

        let ring = NSBezierPath(ovalIn: NSRect(x: bounds.midX - 21, y: bounds.midY - 21, width: 42, height: 42))
        NSColor(white: 0.25, alpha: 1).setStroke()
        ring.lineWidth = 1.5
        ring.stroke()
        let circle = NSRect(x: bounds.midX - 17, y: bounds.midY - 17, width: 34, height: 34)
        NSBezierPath(ovalIn: circle).addClip()
        // Crop away the artwork's transparent square corners inside the circle.
        image?.draw(in: circle.insetBy(dx: -5, dy: -5), from: .zero,
                    operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        startMouse = NSEvent.mouseLocation
        startOrigin = window?.frame.origin ?? .zero
        didDrag = false
        setExpanded(true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - startMouse.x
        let dy = mouse.y - startMouse.y
        if hypot(dx, dy) > 4 { didDrag = true }
        if didDrag { window.setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy)) }
    }

    override func mouseUp(with event: NSEvent) {
        if didDrag, let window {
            Self.keepOnScreen(window)
            UserDefaults.standard.set([Double(window.frame.minX), Double(window.frame.minY)], forKey: "floatingLauncherOrigin")
            didDrag = false
            let mouse = NSEvent.mouseLocation
            setExpanded(window.frame.contains(mouse))
        } else {
            onToggle?()
        }
    }

    override func accessibilityPerformPress() -> Bool {
        onToggle?()
        return true
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let show = NSMenuItem(title: L10n.tr("打开 Nest Launcher"), action: #selector(showLauncher), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        let hide = NSMenuItem(title: L10n.tr("隐藏桌面悬浮球"), action: #selector(hideLauncher), keyEquivalent: "")
        hide.target = self
        menu.addItem(hide)
        let settings = NSMenuItem(title: L10n.tr("设置…"), action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: L10n.tr("退出 Nest Launcher"), action: #selector(quitLauncher), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func showLauncher() { onShow?() }
    @objc private func quitLauncher() { NSApp.terminate(nil) }
    @objc private func hideLauncher() { onHide?() }
    @objc private func openSettings() { onSettings?() }

    static func keepOnScreen(_ window: NSWindow) {
        let screens = NSScreen.screens
        guard let screen = screens.max(by: {
            intersectionArea($0.visibleFrame, window.frame) < intersectionArea($1.visibleFrame, window.frame)
        }) else { return }
        let bounds = screen.visibleFrame
        var origin = NSPoint(
            x: min(max(window.frame.minX, bounds.minX), bounds.maxX - window.frame.width),
            y: min(max(window.frame.minY, bounds.minY), bounds.maxY - window.frame.height)
        )
        let distances: [(Edge, CGFloat)] = [
            (.left, abs(origin.x - bounds.minX)),
            (.right, abs(bounds.maxX - origin.x - window.frame.width)),
            (.bottom, abs(origin.y - bounds.minY)),
            (.top, abs(bounds.maxY - origin.y - window.frame.height))
        ]
        let edge = distances.min(by: { $0.1 < $1.1 })!.0
        let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
        let size = edge == .left || edge == .right
            ? NSSize(width: 56, height: 96) : NSSize(width: 96, height: 56)
        origin = NSPoint(
            x: min(max(center.x - size.width / 2, bounds.minX), bounds.maxX - size.width),
            y: min(max(center.y - size.height / 2, bounds.minY), bounds.maxY - size.height)
        )
        switch edge {
        case .left: origin.x = bounds.minX
        case .right: origin.x = bounds.maxX - size.width
        case .bottom: origin.y = bounds.minY
        case .top: origin.y = bounds.maxY - size.height
        }
        window.setFrame(NSRect(origin: origin, size: size), display: true)
        if let icon = window.contentView as? FloatingLauncherIcon {
            icon.edge = edge
            icon.updateTrackingAreas()
            icon.needsDisplay = true
        }
    }

    private static func intersectionArea(_ a: NSRect, _ b: NSRect) -> CGFloat {
        let intersection = a.intersection(b)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}
