import Foundation

/// 一排排格子的排版：給定可用寬度和格子數，算出幾欄、每格多大，
/// 以及「座標 ↔ 第幾格」的換算。介面畫格子和判斷滑鼠點到哪格都用它，兩邊不會對不上。
public struct GridMetrics: Equatable, Sendable {
    public let cols: Int
    public let cell: CGFloat
    public let gap: CGFloat
    public let count: Int

    public init(width: CGFloat, count: Int, minCell: CGFloat = 32, gap: CGFloat = 4) {
        let c = max(1, Int((width + gap) / (minCell + gap)))
        self.cols = c
        self.cell = max(8, (width - CGFloat(c - 1) * gap) / CGFloat(c))
        self.gap = gap
        self.count = max(0, count)
    }

    public var pitch: CGFloat { cell + gap }
    public var rows: Int { count == 0 ? 0 : (count + cols - 1) / cols }
    public var height: CGFloat { rows == 0 ? 0 : CGFloat(rows) * pitch - gap }

    public func indices(inRow row: Int) -> Range<Int> {
        let lo = row * cols
        return lo..<min(count, lo + cols)
    }

    public func row(of index: Int) -> Int { index / cols }

    /// 座標落在哪一格；落在格子之間的縫或範圍外回傳 nil。
    public func index(at p: CGPoint) -> Int? {
        guard p.x >= 0, p.y >= 0 else { return nil }
        let col = Int(p.x / pitch)
        let row = Int(p.y / pitch)
        guard col < cols else { return nil }
        guard p.x - CGFloat(col) * pitch <= cell, p.y - CGFloat(row) * pitch <= cell else { return nil }
        let i = row * cols + col
        return i < count ? i : nil
    }

    public func center(of index: Int) -> CGPoint {
        let col = index % cols
        let row = index / cols
        return CGPoint(x: CGFloat(col) * pitch + cell / 2, y: CGFloat(row) * pitch + cell / 2)
    }
}
