import AppKit
import SwiftUI

@MainActor
final class PanelController {
    static let shared = PanelController()

    private let panel: QuickReminderPanel
    private var clickMonitor: Any?
    private var isVisible = false

    private init() {
        panel = QuickReminderPanel()
        setupContentView()
    }

    private func setupContentView() {
        let rootView = QuickReminderView().environment(\.colorScheme, .dark)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = Self.cornerRadius
        container.layer?.masksToBounds = true

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = Self.cornerRadius
            glass.contentView = hostingView
            container.addSubview(glass)
            glass.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                glass.topAnchor.constraint(equalTo: container.topAnchor),
                glass.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                glass.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                glass.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ])
        } else {
            let effectView = NSVisualEffectView()
            effectView.material = .hudWindow
            effectView.state = .active
            effectView.wantsLayer = true
            effectView.layer?.cornerRadius = Self.cornerRadius
            effectView.layer?.masksToBounds = true
            container.addSubview(effectView)
            effectView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                effectView.topAnchor.constraint(equalTo: container.topAnchor),
                effectView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                effectView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                effectView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ])
            container.addSubview(hostingView)
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                hostingView.topAnchor.constraint(equalTo: container.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ])
        }

        panel.contentView = container
    }

    private static let cornerRadius: CGFloat = 28

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        guard !isVisible else { return }
        centerOnMouseScreen()
        panel.makeKeyAndOrderFront(nil)
        isVisible = true
        NotificationCenter.default.post(name: .panelWillShow, object: nil)
        installClickMonitor()
    }

    func hide() {
        guard isVisible else { return }
        removeClickMonitor()
        isVisible = false
        NotificationCenter.default.post(name: .panelDidHide, object: nil)

        let capturedPanel = panel
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 130_000_000)
            capturedPanel.orderOut(nil)
        }
    }

    private func centerOnMouseScreen() {
        let screen = screenWithMouse()
        let frame = screen.visibleFrame
        let panelSize = panel.frame.size
        let x = frame.midX - panelSize.width / 2
        let y = frame.midY + frame.height * 0.10
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func screenWithMouse() -> NSScreen {
        let loc = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func installClickMonitor() {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.hide()
            }
        }
    }

    private func removeClickMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }
}

extension Notification.Name {
    static let panelWillShow = Notification.Name("PanelWillShow")
    static let panelDidHide = Notification.Name("PanelDidHide")
}
