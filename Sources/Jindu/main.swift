import AppKit

// 純菜單欄 app：不出現在 Dock，也沒有主視窗。
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    // app.delegate 是弱引用；run() 不會返回，delegate 在這個作用域裡一直活著。
    withExtendedLifetime(delegate) {
        app.run()
    }
}
