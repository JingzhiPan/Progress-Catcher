import AppKit
import JinduCore
import SwiftUI

enum Route: Equatable {
    case home
    case project(UUID)
    case settings
}

/// 無邊框、浮在最上層、不搶走其他 app 焦點的小視窗。
final class FloatingPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Esc
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// 視窗不是焦點時，第一下點擊也直接生效（否則置頂時每次都要先點一下「喚醒」）。
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// 管面板的三種狀態：
/// - 未置頂：像彈出選單，出現在菜單欄圖標下面，點別處就收起。
/// - 置頂：一直浮在最上層，可拖動、可調大小，位置會記住。
/// - 迷你條：置頂狀態下的小尺寸，只顯示當前分組。
@MainActor
final class PanelController: NSObject, ObservableObject, NSWindowDelegate {
    @Published var route: Route = .home
    @Published private(set) var pinned = false
    @Published private(set) var mini = false
    /// 迷你條顯示哪個項目；nil 表示跟著菜單欄那個走。
    @Published var miniProjectID: UUID?

    weak var statusButton: NSStatusBarButton?

    private let store: Store
    private let panel: FloatingPanel
    private let defaults = UserDefaults.standard
    private var outsideMonitor: Any?
    private var lastHide = Date.distantPast
    private var settingFrame = false

    private static let fullMin = NSSize(width: 300, height: 280)
    private static let miniMin = NSSize(width: 200, height: 76)
    private static let defaultFull = NSSize(width: 380, height: 540)
    private static let defaultMini = NSSize(width: 300, height: 150)

    private enum Key {
        static let pinned = "pinned"
        static let mini = "mini"
        static let anchor = "pinnedTopRight"
        static let fullSize = "pinnedFullSize"
        static let miniSize = "pinnedMiniSize"
        static let popoverSize = "popoverSize"
    }

    init(store: Store) {
        self.store = store
        panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: Self.defaultFull),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: true
        )
        super.init()

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .utilityWindow
        // 所有桌面都看得到，別的 app 全螢幕時也能浮在上面。
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = Self.fullMin
        panel.delegate = self
        panel.onCancel = { [weak self] in
            guard let self, !self.pinned else { return }
            self.hide(reason: "esc")
        }

        let root = RootView()
            .environmentObject(store)
            .environmentObject(self)
        let hosting = FirstMouseHostingView(rootView: root)
        hosting.sizingOptions = []
        panel.contentView = hosting
    }

    var window: NSWindow { panel }
    var isVisible: Bool { panel.isVisible }

    // MARK: 顯示／隱藏

    /// 啟動時：上次退出前是置頂的，就原樣擺回去。
    func restore() {
        guard defaults.bool(forKey: Key.pinned) else { return }
        pinned = true
        mini = defaults.bool(forKey: Key.mini)
        show()
    }

    func toggle() {
        if panel.isVisible {
            hide()
        } else if Date().timeIntervalSince(lastHide) > 0.2 {
            show()
        }
    }

    func show() {
        let frame: NSRect
        if pinned {
            frame = pinnedFrame(size: savedSize(mini ? Key.miniSize : Key.fullSize) ?? (mini ? Self.defaultMini : Self.defaultFull))
        } else {
            frame = frameUnderStatusItem(size: savedSize(Key.popoverSize) ?? Self.defaultFull)
        }
        panel.minSize = mini ? Self.miniMin : Self.fullMin
        apply(frame)
        panel.becomesKeyOnlyIfNeeded = pinned
        panel.orderFrontRegardless()
        if !pinned {
            panel.makeKey()
            installOutsideMonitor()
        }
    }

    func hide(reason: String = "toggle") {
        if DebugProbe.enabled { print("  [hide] \(reason) key=\(panel.isKeyWindow) active=\(NSApp.isActive)") }
        removeOutsideMonitor()
        panel.orderOut(nil)
        lastHide = Date()
        store.flush()
    }

    // MARK: 置頂／迷你條

    func setPinned(_ on: Bool) {
        guard on != pinned else { return }
        if on {
            pinned = true
            panel.becomesKeyOnlyIfNeeded = true
            removeOutsideMonitor()
            saveGeometry()
        } else {
            if mini { setMini(false) }
            pinned = false
            panel.becomesKeyOnlyIfNeeded = false
            // 留在原地，變回「點別處就收起」；下次打開會回到菜單欄圖標下面。
            if panel.isVisible {
                panel.makeKey()
                installOutsideMonitor()
            }
        }
        defaults.set(pinned, forKey: Key.pinned)
    }

    func setMini(_ on: Bool) {
        guard on != mini else { return }
        if on && !pinned { setPinned(true) }
        saveGeometry()

        if on {
            if case .project(let id) = route { miniProjectID = id } else { miniProjectID = nil }
        }
        mini = on
        defaults.set(mini, forKey: Key.mini)

        // 兩種大小共用右上角，切換時不會跳來跳去。
        let size = savedSize(on ? Key.miniSize : Key.fullSize) ?? (on ? Self.defaultMini : Self.defaultFull)
        let current = panel.frame
        panel.minSize = on ? Self.miniMin : Self.fullMin
        apply(clamped(NSRect(x: current.maxX - size.width, y: current.maxY - size.height, width: size.width, height: size.height)))
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        if !pinned && panel.isVisible { hide(reason: "resignKey") }
    }

    func windowDidMove(_ notification: Notification) {
        if !settingFrame { saveGeometry() }
    }

    func windowDidResize(_ notification: Notification) {
        if !settingFrame { saveGeometry() }
    }

    // MARK: 位置與大小

    private func saveGeometry() {
        let frame = panel.frame
        if pinned {
            defaults.set(NSStringFromPoint(NSPoint(x: frame.maxX, y: frame.maxY)), forKey: Key.anchor)
            defaults.set(NSStringFromSize(frame.size), forKey: mini ? Key.miniSize : Key.fullSize)
        } else if panel.isVisible {
            defaults.set(NSStringFromSize(frame.size), forKey: Key.popoverSize)
        }
    }

    private func savedSize(_ key: String) -> NSSize? {
        guard let raw = defaults.string(forKey: key) else { return nil }
        let size = NSSizeFromString(raw)
        return size.width >= Self.miniMin.width && size.height >= Self.miniMin.height ? size : nil
    }

    private func pinnedFrame(size: NSSize) -> NSRect {
        guard let raw = defaults.string(forKey: Key.anchor) else { return frameUnderStatusItem(size: size) }
        let anchor = NSPointFromString(raw)
        return clamped(NSRect(x: anchor.x - size.width, y: anchor.y - size.height, width: size.width, height: size.height))
    }

    private func frameUnderStatusItem(size: NSSize) -> NSRect {
        if let buttonFrame = statusButton?.window?.frame, buttonFrame.width > 0 {
            return clamped(NSRect(x: buttonFrame.midX - size.width / 2, y: buttonFrame.minY - 6 - size.height,
                                  width: size.width, height: size.height))
        }
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        return NSRect(x: visible.maxX - size.width - 12, y: visible.maxY - size.height - 6, width: size.width, height: size.height)
    }

    /// 把視窗推回螢幕可見範圍內（外接螢幕拔掉之後不至於找不到）。
    private func clamped(_ rect: NSRect) -> NSRect {
        let screens = NSScreen.screens
        let screen = screens.max { a, b in
            a.frame.intersection(rect).width * a.frame.intersection(rect).height
                < b.frame.intersection(rect).width * b.frame.intersection(rect).height
        }
        guard let visible = (screen ?? NSScreen.main)?.visibleFrame else { return rect }
        var r = rect
        r.size.width = min(r.width, visible.width)
        r.size.height = min(r.height, visible.height)
        r.origin.x = min(max(r.minX, visible.minX), visible.maxX - r.width)
        r.origin.y = min(max(r.minY, visible.minY), visible.maxY - r.height)
        return r
    }

    private func apply(_ frame: NSRect) {
        settingFrame = true
        panel.setFrame(frame, display: true)
        settingFrame = false
        panel.invalidateShadow()
    }

    // MARK: 點面板外面就收起（只在未置頂時）

    private func installOutsideMonitor() {
        guard outsideMonitor == nil else { return }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.pinned, self.panel.isVisible else { return }
                self.hide(reason: "outsideClick")
            }
        }
    }

    private func removeOutsideMonitor() {
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        outsideMonitor = nil
    }
}
