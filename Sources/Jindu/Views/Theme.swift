import AppKit
import SwiftUI

/// 配色沿用原來那個網頁版進度表的暖色調，明暗跟隨系統。
enum Theme {
    static let bg = dyn(0xf7f6f3, 0x1b1a18)
    static let fg = dyn(0x2d2b27, 0xe2dfd8)
    static let dim = dyn(0x918d85, 0x8a857d)
    static let surface = dyn(0xffffff, 0x262523)
    static let border = dyn(0xe4e0da, 0x3c3a36)
    static let accent = dyn(0xd4847a, 0xe8a49c)
    static let accentSoft = dyn(0xfce8e5, 0x2e2224)
    static let onAccent = dyn(0xffffff, 0x1b1a18)
    static let danger = dyn(0xbf5b4b, 0xd4796a)
    static let dangerSoft = dyn(0xfceeed, 0x2c2220)
    static let input = dyn(0xffffff, 0x302e2b)

    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: 1
        )
    }
}

// MARK: 共用小元件

/// 表頭上的小圖標按鈕。
struct IconButton: View {
    let symbol: String
    var help: String = ""
    var active: Bool = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(active ? Theme.accent : Theme.dim)
                .frame(width: 24, height: 24)
                .background(hover ? Theme.border.opacity(0.7) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

/// 「…」選單，外觀和 IconButton 一致。
struct MoreMenu<Items: View>: View {
    @ViewBuilder var items: () -> Items

    var body: some View {
        Menu {
            items()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(Theme.dim)
        .help("更多")
    }
}

struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Theme.input, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border, lineWidth: 1))
    }
}

struct PillButtonStyle: ButtonStyle {
    enum Kind { case accent, danger, quiet }
    var kind: Kind = .accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: 6))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }

    private var foreground: Color {
        switch kind {
        case .accent: return Theme.onAccent
        case .danger: return Theme.danger
        case .quiet: return Theme.dim
        }
    }

    private var background: Color {
        switch kind {
        case .accent: return Theme.accent
        case .danger: return Theme.dangerSoft
        case .quiet: return Theme.border.opacity(0.5)
        }
    }
}

struct ProgressBar: View {
    let fraction: Double
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.border)
                Capsule().fill(Theme.accent)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}

/// 卡片底：白底、細邊、圓角。
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border, lineWidth: 1))
    }
}

/// 墊在表頭底下的拖動區：按住空白處可以拖動整個面板。
struct DragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { HandleView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class HandleView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}

/// 表頭：左邊返回鍵（可選），中間標題，右邊一排按鈕。
struct HeaderBar<Center: View, Trailing: View>: View {
    var onBack: (() -> Void)?
    var height: CGFloat = 40
    @ViewBuilder var center: () -> Center
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 4) {
            if let onBack {
                IconButton(symbol: "chevron.left", help: "返回", action: onBack)
            }
            center()
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(.horizontal, 10)
        .frame(height: height)
        .background(DragHandle())
        .overlay(alignment: .bottom) { Theme.border.frame(height: 1) }
    }
}

/// 置頂、收成迷你條這兩個視窗按鈕。
struct WindowButtons: View {
    @EnvironmentObject var panel: PanelController

    var body: some View {
        if panel.pinned {
            IconButton(symbol: "rectangle.compress.vertical", help: "收成迷你條") { panel.setMini(true) }
        }
        IconButton(symbol: panel.pinned ? "pin.fill" : "pin",
                   help: panel.pinned ? "取消置頂" : "置頂在最上層",
                   active: panel.pinned) {
            panel.setPinned(!panel.pinned)
        }
    }
}

/// 拖動排序用：拖著 A 經過 B 時，把 A 挪到 B 的位置。
struct ReorderDropDelegate: DropDelegate {
    let target: UUID
    @Binding var dragging: UUID?
    let move: (UUID, UUID) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        withAnimation(.easeInOut(duration: 0.15)) { move(dragging, target) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

extension String {
    /// 只留半形數字，給起止頁碼輸入框用。
    var digitsOnly: String { filter { ("0"..."9").contains($0) } }
}
