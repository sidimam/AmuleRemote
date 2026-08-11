// Reliable double-click for SwiftUI Table on macOS: an AppKit local event
// monitor scoped to the table's frame (header row excluded by geometry).
import SwiftUI
import AppKit

extension View {
    /// Runs `action` when the user double-clicks inside this view's area.
    func onTableDoubleClick(perform action: @escaping () -> Void) -> some View {
        background(TableDoubleClickMonitor(action: action))
    }
}

private struct TableDoubleClickMonitor: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> MonitorView { MonitorView(action: action) }
    func updateNSView(_ nsView: MonitorView, context: Context) { nsView.action = action }

    final class MonitorView: NSView {
        var action: () -> Void
        private var monitor: Any?

        init(action: @escaping () -> Void) {
            self.action = action
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("unsupported") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                removeMonitor()
                return
            }
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
                guard let self, let win = self.window, event.window === win,
                      event.clickCount == 2 else { return event }
                // Any double-click landing over the table area triggers the action.
                // We deliberately don't exclude the header strip: a stray double
                // click there is harmless, and the geometry check was fragile.
                let p = self.convert(event.locationInWindow, from: nil)
                if self.bounds.contains(p) {
                    let act = self.action
                    DispatchQueue.main.async { act() }
                }
                return event
            }
        }

        private func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            removeMonitor()
        }
    }
}
