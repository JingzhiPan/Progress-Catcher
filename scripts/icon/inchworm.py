#!/usr/bin/env python3
"""App 圖標：一隻拱起來的毛毛蟲（尺蠖）。

這個腳本是 flat-creature 生成器的一個新「體型」（body plan）。眼睛、配色推導、
路徑平滑都用生成器現成的；這裡只提供它要求的三樣：封閉輪廓、眼睛錨點、附肢。

生成器本身不在這個倉庫裡，用環境變數指過去：

    FLAT_CREATURE_SCRIPTS=<flat-creature 技能的 scripts 資料夾> \
        python3 scripts/icon/inchworm.py --out-dir Assets

輸出：
    inchworm.svg  只有蟲（300x210，給生成器自帶的檢查用）
    icon.svg      1024x1024 的 app 圖標（圓角底板 + 蟲）
    glyph.svg     單色剪影，給菜單欄用
"""
import argparse
import math
import os
import sys

sys.path.insert(0, os.environ.get("FLAT_CREATURE_SCRIPTS", ""))
try:
    import creature as C
except ImportError:
    sys.exit("找不到 flat-creature 的 creature.py；請設定 FLAT_CREATURE_SCRIPTS")

GROUND = 172.0          # 地面線（SVG 座標，y 向下）
STEP = 0.5              # 中心線取樣間距
N_TOP = 44              # 背側取樣點數（固定，狀態之間才能插值）
N_BOTTOM = 36
N_HEAD = 16
N_CAP = 5

# 用 app 自己的暖色：身體是 app 的強調色，深色是 app 的文字色。
C.PALETTES["catcher"] = {"body": "#D4847A", "accent": "#2D2B27", "iris": None}
# 同一隻，眼圈換成和身體互補的灰青色（暖色身體上唯一的冷色，眼睛更跳）
C.PALETTES["catcher-teal"] = {"body": "#D4847A", "accent": "#2D2B27", "iris": None, "shadow": "#3F6E6A"}
C.PALETTES["leaf"] = {"body": "#7FA86B", "accent": "#2D2B27", "iris": None, "shadow": "#D4847A"}
C.PALETTES["cream"] = {"body": "#F7F1E8", "accent": "#2D2B27", "iris": "#D4847A"}

C.PRESETS["inchworm"] = dict(
    C._BASE, plan="worm",
    # body_h 在這個體型裡是「頭的直徑」，眼睛的大小按它算
    body_len=170, body_h=50, eye_ratio=0.30, eye_x=0.0,
    back=0, belly=0, snout=1, tail_h=0, tail="scallop", tail_n=0,
    crest="none", crest_n=0, dorsal="none", ventral="none", mouth="none",
    gaze=0.46, pupil_r=0.56, shine="twin",
    # 體型自己的參數
    tube=13.5,      # 身體半徑
    neck=4.0,       # 頭後面貼地那一段的長度（短：頭直接縮在拱的腳邊）
    fillet=26.0,    # 從地面拐上去的彎的半徑（太小彎的內側會打結）
    rise=22.0,      # 拱的兩條「腿」直的那段
    arch=34.0,      # 拱頂的半徑
    lean=98.0,      # 拐上去轉多少度；大於 90 就是 Ω 那樣上寬下窄
    rear=10.0,      # 尾巴貼地那一段
    segments=8,     # 背上的節數
    bump=0.0,       # 每一節鼓出來多少；試過 0.12，看起來像歪掉而不像分節，所以預設不鼓
    feet=True,
)


def _centerline(p):
    """沿中心線每 STEP 取一點：(x, y, 切線方向)。y 向上，起點在原點、朝東。"""
    th = math.radians(p["lean"])
    plan = [("line", p["neck"]), ("arc", p["fillet"], th), ("line", p["rise"]),
            ("arc", p["arch"], -2 * th), ("line", p["rise"]),
            ("arc", p["fillet"], th), ("line", p["rear"])]
    x = y = h = 0.0
    out = [(x, y, h)]
    for seg in plan:
        if seg[0] == "line":
            n = max(1, int(round(seg[1] / STEP)))
            d = seg[1] / n
            for _ in range(n):
                x += d * math.cos(h)
                y += d * math.sin(h)
                out.append((x, y, h))
        else:
            _, r, turn = seg
            n = max(1, int(round(abs(turn) * r / STEP)))
            dh = turn / n
            for _ in range(n):
                # 弦長步進：先轉半步、走一步、再轉半步
                h += dh / 2
                d = 2 * r * math.sin(abs(dh) / 2)
                x += d * math.cos(h)
                y += d * math.sin(h)
                h += dh / 2
                out.append((x, y, h))
    return out


def _frame(p):
    """頭的圓心、頭半徑、中心線起點（SVG 座標）。"""
    rh = p["body_h"] / 2.0
    xh = C.CX - p["body_len"] / 2.0 + rh
    head = (xh, GROUND - rh)
    start = (xh + rh * 0.42, GROUND - p["tube"])
    return head, rh, start


def _to_svg(p, pt):
    _, _, start = _frame(p)
    return (start[0] + pt[0], start[1] - pt[1])


def _top_radius(p, frac):
    """背側的半徑：一節一節微微鼓起，到尾巴收小一點。"""
    r = p["tube"]
    n = p["segments"]
    swell = 0.5 - 0.5 * math.cos(2 * math.pi * n * frac) if n else 0.0
    taper = 1.0 - 0.18 * max(0.0, (frac - 0.88) / 0.12)
    return r * (1 + p["bump"] * swell) * taper


def worm_head_pts(p):
    head, rh, _ = _frame(p)
    return [(head[0] + rh * math.cos(2 * math.pi * k / 40),
             head[1] + rh * math.sin(2 * math.pi * k / 40)) for k in range(40)]


def worm_eye(p):
    head, rh, _ = _frame(p)
    return (head[0] - rh * 0.06, head[1] - rh * 0.02)


def worm_outline(p):
    head, rh, _ = _frame(p)
    line = _centerline(p)
    total = len(line) - 1

    def offset(i, r):
        x, y, h = line[i]
        return _to_svg(p, (x - math.sin(h) * r, y + math.cos(h) * r))

    # 背側從哪裡開始露出頭的圓外面
    first = 0
    for i in range(total + 1):
        q = offset(i, _top_radius(p, i / total))
        if math.hypot(q[0] - head[0], q[1] - head[1]) > rh + 4.0:
            first = i
            break
    junction = offset(first, _top_radius(p, first / total))
    a_end = math.atan2(junction[1] - head[1], junction[0] - head[0]) % (2 * math.pi)

    pts = []
    # 頭：從最底下那一點（貼地）繞過臉、頭頂，到脖子
    a0 = math.pi / 2
    span = (a_end - a0) % (2 * math.pi)
    for k in range(N_HEAD):
        a = a0 + span * k / N_HEAD
        pts.append((head[0] + rh * math.cos(a), head[1] + rh * math.sin(a)))
    # 背
    for k in range(N_TOP):
        i = first + int(round((total - first) * k / (N_TOP - 1)))
        pts.append(offset(i, _top_radius(p, i / total)))
    # 尾端圓頭
    ex, ey, eh = line[-1]
    r_top, r_bot = _top_radius(p, 1.0), p["tube"]
    for k in range(1, N_CAP + 1):
        a = eh + math.pi / 2 - math.pi * k / (N_CAP + 1)
        r = C.lerp(r_top, r_bot, k / (N_CAP + 1))
        pts.append(_to_svg(p, (ex + r * math.cos(a), ey + r * math.sin(a))))
    # 肚子（貼地、拱的內側），從尾巴回到頭
    for k in range(N_BOTTOM):
        i = total - int(round(total * k / (N_BOTTOM - 1)))
        pts.append(offset(i, -p["tube"]))
    return pts


def worm_feet(p):
    """小短腿：前後各兩隻，畫在身體底下，只露出地面線以下那一點。"""
    if not p["feet"]:
        return []
    _, rh, start = _frame(p)
    line = _centerline(p)
    end_x = _to_svg(p, line[-1][:2])[0]
    r = p["tube"] * 0.32
    xs = [start[0] + p["neck"] + d for d in (2.0, 13.0)]
    xs += [end_x - d for d in (15.0, 4.0)]
    out = []
    for x in xs:
        ring = [(x + r * math.cos(2 * math.pi * k / C.N_LOBE),
                 GROUND - r * 0.15 + r * math.sin(2 * math.pi * k / C.N_LOBE))
                for k in range(C.N_LOBE)]
        out.append(C.catmull(ring))
    return out


C.PLANS["worm"] = {"outline": worm_outline, "eye": worm_eye, "eye_hull": worm_head_pts}


def _parts(p, pal, eye=True):
    parts = []
    for i, d in enumerate(worm_feet(p)):
        parts.append('<path id="foot-%d" d="%s" fill="%s"/>' % (i, d, pal["accent"]))
    parts.append('<path id="body" d="%s" fill="%s"/>' % (C.catmull(worm_outline(p)), pal["body"]))
    if eye:
        parts.append(C.eye_group(p, pal))
    return "".join(parts)


def _bbox(p):
    pts = worm_outline(p)
    xs = [q[0] for q in pts]
    ys = [q[1] for q in pts]
    foot = p["tube"] * 0.32 if p["feet"] else 0
    return min(xs), min(ys), max(xs), max(ys) + foot * 0.85


def creature_svg(p, pal):
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d" role="img">'
            '<title>inchworm</title><g id="creature">%s</g></svg>'
            % (C.VIEW_W, C.VIEW_H, C.VIEW_W, C.VIEW_H, _parts(p, pal)))


def _placed(p, inner, box, fill_w, facing):
    """把蟲縮放、置中放進 box=(x, y, w, h)；寬度佔 fill_w。"""
    x0, y0, x1, y1 = _bbox(p)
    w, h = x1 - x0, y1 - y0
    bx, by, bw, bh = box
    s = bw * fill_w / w
    tx = bx + (bw - w * s) / 2 - x0 * s
    ty = by + (bh - h * s) / 2 - y0 * s
    if facing == "right":
        # 以蟲自己的中線左右翻面
        mid = x0 + x1
        return '<g transform="translate(%g,%g) scale(%g) translate(%g,0) scale(-1,1)">%s</g>' % (tx, ty, s, mid, inner)
    return '<g transform="translate(%g,%g) scale(%g)">%s</g>' % (tx, ty, s, inner)


def icon_svg(p, pal, plate, facing="right"):
    """macOS 圖標：1024 畫布，中間 824 的圓角方塊，四周留白是系統慣例。"""
    plate_rect = '<path id="plate" d="%s" fill="%s"/>' % (_squircle(100, 100, 824, 824, 185), plate)
    worm = _placed(p, _parts(p, pal), (100, 100, 824, 824), 0.74, facing)
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024" role="img">'
            '<title>Progress Catcher</title>%s%s</svg>' % (plate_rect, worm))


GLYPH_EYE = 0.50        # 菜單欄剪影裡眼睛那個洞的半徑（頭半徑的比例）；比彩色版大，小尺寸才看得見


def _glyph_geometry(p, facing):
    """菜單欄剪影的幾何：身體輪廓（不畫腿，15pt 高的時候腿只是雜點）加一個眼睛的洞。
    座標已經平移到左上角為原點、按 facing 翻好面。回傳 (寬, 高, 輪廓點, 眼睛圓心, 眼睛半徑)。"""
    pts = worm_outline(p)
    xs = [q[0] for q in pts]
    ys = [q[1] for q in pts]
    pad = 1.0
    x0, x1, y0, y1 = min(xs) - pad, max(xs) + pad, min(ys) - pad, max(ys) + pad
    fx = (lambda x: x1 - x) if facing == "right" else (lambda x: x - x0)
    _, rh, _ = _frame(p)
    ex, ey = worm_eye(p)
    outline = [(fx(x), y - y0) for x, y in pts]
    return x1 - x0, y1 - y0, outline, (fx(ex), ey - y0), rh * GLYPH_EYE


def glyph_svg(p, facing="right"):
    """菜單欄用的單色剪影：整隻蟲一個顏色，眼睛挖成洞。"""
    w, h, outline, eye, r = _glyph_geometry(p, facing)
    mask = ('<mask id="hole"><rect x="0" y="0" width="%g" height="%g" fill="#FFFFFF"/>'
            '<circle cx="%g" cy="%g" r="%g" fill="#000000"/></mask>' % (w, h, eye[0], eye[1], r))
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %g %g" width="%g" height="%g" role="img">'
            '<title>inchworm glyph</title><defs>%s</defs>'
            '<path id="body" d="%s" fill="#1A1A1A" mask="url(#hole)"/></svg>'
            % (w, h, w, h, mask, C.catmull(outline)))


def glyph_swift(p, facing="right"):
    """同一個剪影，寫成 Swift 原始碼：app 直接用向量畫，不用另外帶圖檔。"""
    w, h, pts, eye, r = _glyph_geometry(p, facing)
    n = len(pts)
    rows = []
    for i in range(n):
        p0, p1, p2, p3 = pts[(i - 1) % n], pts[i], pts[(i + 1) % n], pts[(i + 2) % n]
        c1 = (p1[0] + (p2[0] - p0[0]) / 6.0, p1[1] + (p2[1] - p0[1]) / 6.0)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6.0, p2[1] - (p3[1] - p1[1]) / 6.0)
        rows.append("        (%.2f, %.2f, %.2f, %.2f, %.2f, %.2f)," % (c1[0], c1[1], c2[0], c2[1], p2[0], p2[1]))
    return SWIFT_TEMPLATE % dict(w=w, h=h, sx=pts[0][0], sy=pts[0][1], ex=eye[0], ey=eye[1], er=r,
                                 curves="\n".join(rows))


SWIFT_TEMPLATE = """// 由 scripts/icon/inchworm.py 產生（./scripts/make-icon.sh），不要手改。
// 菜單欄圖標：和 app 圖標同一隻拱起來的毛毛蟲，單色剪影，眼睛是鏤空的。
import AppKit

enum MenuBarGlyph {
    /// 設計座標的畫布大小（y 向下）
    private static let canvas = CGSize(width: %(w).2f, height: %(h).2f)
    private static let start = CGPoint(x: %(sx).2f, y: %(sy).2f)
    /// 身體輪廓：一段段三次貝茲曲線（控制點 1、控制點 2、終點）
    private static let curves: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
%(curves)s
    ]
    private static let eye = (center: CGPoint(x: %(ex).2f, y: %(ey).2f), radius: CGFloat(%(er).2f))

    /// 模板圖：系統會按菜單欄的深淺自動上色。
    static func image(height: CGFloat = 15) -> NSImage {
        let scale = height / canvas.height
        let size = NSSize(width: (canvas.width * scale).rounded(.up), height: height)
        let image = NSImage(size: size, flipped: true) { _ in
            let transform = AffineTransform(scale: scale)
            let body = NSBezierPath()
            body.move(to: start)
            for c in curves {
                body.curve(to: CGPoint(x: c.4, y: c.5),
                           controlPoint1: CGPoint(x: c.0, y: c.1),
                           controlPoint2: CGPoint(x: c.2, y: c.3))
            }
            body.close()
            body.transform(using: transform)
            NSColor.black.setFill()
            body.fill()

            // 眼睛：把這一塊擦成透明
            let hole = NSBezierPath(ovalIn: NSRect(x: eye.center.x - eye.radius, y: eye.center.y - eye.radius,
                                                   width: eye.radius * 2, height: eye.radius * 2))
            hole.transform(using: transform)
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            hole.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "進度表"
        return image
    }
}
"""


def _squircle(x, y, w, h, r):
    """圓角方塊。用貝茲曲線把圓角拉長一點，比正圓角更接近系統圖標的形狀。"""
    k = r * 1.28          # 圓角佔邊的長度
    c = r * 0.36          # 控制點離角的距離
    f = lambda a, b: "%g,%g" % (a, b)
    return ("M%s L%s C%s %s %s L%s C%s %s %s L%s C%s %s %s L%s C%s %s %s Z" % (
        f(x + k, y), f(x + w - k, y),
        f(x + w - c, y), f(x + w, y + c), f(x + w, y + k),
        f(x + w, y + h - k),
        f(x + w, y + h - c), f(x + w - c, y + h), f(x + w - k, y + h),
        f(x + k, y + h),
        f(x + c, y + h), f(x, y + h - c), f(x, y + h - k),
        f(x, y + k),
        f(x, y + c), f(x + c, y), f(x + k, y)))


def sheet_svg(p, variants, facing="right"):
    """幾個配色方案並排，挑的時候用。variants: [(palette 名, 底板色)]"""
    cells = []
    for i, (name, plate) in enumerate(variants):
        inner = icon_svg(p, C.PALETTES[name], plate, facing)
        inner = inner[inner.index("</title>") + 8:-6]
        cells.append('<g transform="translate(%d,0)">%s</g>' % (i * 1024, inner))
    w = 1024 * len(variants)
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d 1024" width="%d" height="1024">'
            '<rect x="0" y="0" width="%d" height="1024" fill="#DDD9D2"/>%s</svg>' % (w, w, w, "".join(cells)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out-dir", default=".")
    # 預設：米白的蟲放在 app 強調色的底板上——和面板裡「蓋了章的格子」是同一組顏色
    ap.add_argument("--palette", default="cream", choices=list(C.PALETTES))
    ap.add_argument("--plate", default="#D4847A", help="圖標底板顏色")
    ap.add_argument("--facing", default="right", choices=["left", "right"])
    ap.add_argument("--name", default="", help="輸出檔名前綴（比較幾個方案時用）")
    for key in ("tube", "neck", "fillet", "rise", "arch", "lean", "rear", "bump",
                "body_h", "eye_ratio", "gaze", "pupil_r"):
        ap.add_argument("--" + key.replace("_", "-"), type=float, default=None)
    ap.add_argument("--segments", type=int, default=None)
    ap.add_argument("--no-feet", action="store_true")
    ap.add_argument("--sheet", default="", help="並排比較：palette@底板色,palette@底板色…")
    ap.add_argument("--swift-out", default="", help="把菜單欄剪影寫成 Swift 原始碼的路徑")
    ap.add_argument("--shine", default=None, choices=list(C.SHINES))
    a = ap.parse_args()

    p = dict(C.PRESETS["inchworm"])
    for key in ("tube", "neck", "fillet", "rise", "arch", "lean", "rear", "bump",
                "body_h", "eye_ratio", "gaze", "pupil_r", "segments", "shine"):
        if getattr(a, key) is not None:
            p[key] = getattr(a, key)
    if a.no_feet:
        p["feet"] = False
    pal = C.PALETTES[a.palette]

    os.makedirs(a.out_dir, exist_ok=True)
    outputs = {
        "inchworm.svg": creature_svg(p, pal),
        "icon.svg": icon_svg(p, pal, a.plate, a.facing),
        "glyph.svg": glyph_svg(p, a.facing),
    }
    if a.sheet:
        variants = [tuple(v.split("@")) for v in a.sheet.split(",")]
        outputs = {"sheet.svg": sheet_svg(p, variants, a.facing)}
    if a.swift_out and not a.sheet:
        with open(a.swift_out, "w") as fh:
            fh.write(glyph_swift(p, a.facing))
        print("wrote", a.swift_out)
    for name, svg in outputs.items():
        path = os.path.join(a.out_dir, a.name + name)
        with open(path, "w") as fh:
            fh.write(svg)
        print("wrote", path)


if __name__ == "__main__":
    main()
