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
        let rootView = QuickReminderView()
        let hostingView = NSHostingView(rootView: rootView)

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = 24
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            glass.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.topAnchor.constraint(equalTo: glass.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
                hostingView.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            ])
            panel.contentView = glass
        } else {
            let effectView = NSVisualEffectView()
            effectView.material = .hudWindow
            effectView.state = .active
            effectView.wantsLayer = true
            effectView.layer?.cornerRadius = 24
            effectView.layer?.masksToBounds = true
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            effectView.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.topAnchor.constraint(equalTo: effectView.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
                hostingView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            ])
            panel.contentView = effectView
        }
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        guard !isVisible else { return }
        centerOnMouseScreen()
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        isVisible = true
        NotificationCenter.default.post(name: .panelWillShow, object: nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        installClickMonitor()
    }

    func hide() {
        guard isVisible else { return }
        removeClickMonitor()
        isVisible = false
        NotificationCenter.default.post(name: .panelDidHide, object: nil)

        let capturedPanel = panel
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            capturedPanel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                capturedPanel.orderOut(nil)
                capturedPanel.alphaValue = 1
            }
        })
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
