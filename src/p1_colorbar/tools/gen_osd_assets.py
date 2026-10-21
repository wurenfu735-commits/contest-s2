# -*- coding: utf-8 -*-
"""
gen_osd_assets.py  ——  B4 OSD 资源生成器（可重跑，产物全部可复现）

做四件事：
  1) 从安路官方例程 anlogic_logo_rom.v 里取出“安路”标识位图，
     量化成品牌两色（深蓝 #1C2D4E / 红 #ED1C24），重编码为 2bit/像素 ROM；
  2) 生成 rtl/osd_logo_rom.v（纯 case 查表，综合成 LUT/ERAM，可读性优于压缩网格）；
  3) 用 tools/osd_overlay.tpl.v 生成 rtl/osd_overlay.v（自动注入自建 5x7 字模 + 两行文案）；
  4) 用同一套几何/配色规则做“黄金模型”：
       - 输出 tools/osd_preview.png（1280x720 合成预览图，人眼验收用）
       - 输出 tb/unit/osd_tb_expect_*.vh（像素分类计数 + 整帧哈希，给自检 tb 用）

用法：
    python gen_osd_assets.py [官方 anlogic_logo_rom.v 路径]

说明：Logo 位图属于“主办方标识素材”，我们只复用其图形数据并在此注明来源；
      渲染逻辑（坐标/掩膜/描边/字模/优先级/流水）全部自研，见 osd_overlay.v。
"""
import os
import re
import sys
import zlib
import struct

# ------------------------------------------------------------------ 路径
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)                      # .../src/p1_colorbar
OUT_RTL = os.path.join(ROOT, "rtl")
OUT_TB = os.path.join(ROOT, "tb", "unit")
TPL = os.path.join(HERE, "osd_overlay.tpl.v")

DEFAULT_OFFICIAL_ROM = os.path.join(
    HERE, "vendor", "anlogic_logo_rom.v")

# ------------------------------------------------------------------ 几何 / 配色（与 RTL 参数一一对应）
PANEL_X, PANEL_Y, PANEL_W, PANEL_H, PANEL_BW = 16, 16, 208, 156, 2
LOGO_X, LOGO_Y = 24, 24
TEXT_X, TEXT_Y0, TEXT_Y1 = 24, 126, 146
CHAR_ADV, CHAR_NUM, GLYPH_H = 16, 12, 14

C_NAVY = 0x1C2D4E
C_RED = 0xED1C24
C_PLATE = 0xE0E0E0

TEXT0 = "ANLOGIC"       # 第 1 行（不足 12 字符补空格）
TEXT1 = "PH1P35 720P"   # 第 2 行

# 需要输出期望值的两种分辨率：大帧=真实 720p（上板）；小帧=仿真加速用（面板完全在内，
# 所有绘制分支都会被走到，坐标运算与 720p 完全同构）
GEOMETRIES = [(320, 240, "320x240"), (1280, 720, "1280x720")]

# ------------------------------------------------------------------ 自建 5x7 字模（bit4=最左列，行优先，7 行）
FONT = {
    ' ': [0b00000] * 7,
    '-': [0b00000, 0b00000, 0b00000, 0b11111, 0b00000, 0b00000, 0b00000],
    ':': [0b00000, 0b00100, 0b00100, 0b00000, 0b00100, 0b00100, 0b00000],
    '.': [0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00110, 0b00110],
    '0': [0b01110, 0b10001, 0b10011, 0b10101, 0b11001, 0b10001, 0b01110],
    '1': [0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110],
    '2': [0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b01000, 0b11111],
    '3': [0b11110, 0b00001, 0b00001, 0b01110, 0b00001, 0b00001, 0b11110],
    '4': [0b00010, 0b00110, 0b01010, 0b10010, 0b11111, 0b00010, 0b00010],
    '5': [0b11111, 0b10000, 0b11110, 0b00001, 0b00001, 0b10001, 0b01110],
    '6': [0b00110, 0b01000, 0b10000, 0b11110, 0b10001, 0b10001, 0b01110],
    '7': [0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b01000, 0b01000],
    '8': [0b01110, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110],
    '9': [0b01110, 0b10001, 0b10001, 0b01111, 0b00001, 0b00010, 0b01100],
    'A': [0b01110, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001],
    'B': [0b11110, 0b10001, 0b10001, 0b11110, 0b10001, 0b10001, 0b11110],
    'C': [0b01110, 0b10001, 0b10000, 0b10000, 0b10000, 0b10001, 0b01110],
    'D': [0b11110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b11110],
    'E': [0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b11111],
    'F': [0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b10000],
    'G': [0b01110, 0b10001, 0b10000, 0b10111, 0b10001, 0b10001, 0b01111],
    'H': [0b10001, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001],
    'I': [0b01110, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b01110],
    'J': [0b00111, 0b00010, 0b00010, 0b00010, 0b00010, 0b10010, 0b01100],
    'K': [0b10001, 0b10010, 0b10100, 0b11000, 0b10100, 0b10010, 0b10001],
    'L': [0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b11111],
    'M': [0b10001, 0b11011, 0b10101, 0b10101, 0b10001, 0b10001, 0b10001],
    'N': [0b10001, 0b11001, 0b10101, 0b10011, 0b10001, 0b10001, 0b10001],
    'O': [0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110],
    'P': [0b11110, 0b10001, 0b10001, 0b11110, 0b10000, 0b10000, 0b10000],
    'Q': [0b01110, 0b10001, 0b10001, 0b10001, 0b10101, 0b10010, 0b01101],
    'R': [0b11110, 0b10001, 0b10001, 0b11110, 0b10100, 0b10010, 0b10001],
    'S': [0b01111, 0b10000, 0b10000, 0b01110, 0b00001, 0b00001, 0b11110],
    'T': [0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100],
    'U': [0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110],
    'V': [0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01010, 0b00100],
    'W': [0b10001, 0b10001, 0b10001, 0b10101, 0b10101, 0b11011, 0b10001],
    'X': [0b10001, 0b10001, 0b01010, 0b00100, 0b01010, 0b10001, 0b10001],
    'Y': [0b10001, 0b10001, 0b01010, 0b00100, 0b00100, 0b00100, 0b00100],
    'Z': [0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b10000, 0b11111],
}

LOGO_ROW_STRIDE = 160   # 地址 = ly*160 + lx，160=128+32，纯移位加法


# ------------------------------------------------------------------ 1. 解析官方 Logo
def load_logo(path):
    src = open(path, encoding="utf-8", errors="ignore").read()
    pairs = [(int(a), int(v, 16)) for a, v in
             re.findall(r"1?[0-9]*'d(\d+)\s*:\s*O_pixel\s*=\s*2[45]'h([0-9a-fA-F]+)", src)]
    if not pairs:
        raise SystemExit("解析不到官方 ROM 数据，请检查路径: %s" % path)
    W = LOGO_ROW_STRIDE
    opaque = {}
    for a, v in pairs:
        if (v >> 24) & 1:                 # bit24 = 不透明
            opaque[a] = v & 0xFFFFFF
    xs = [a % W for a in opaque]
    ys = [a // W for a in opaque]
    return opaque, W, (min(xs), min(ys), max(xs), max(ys))


def classify(rgb):
    """量化到品牌两色。官方原图只有 navy / red 两大族，抗锯齿中间色按 R 的相对优势归类。"""
    r, g, b = (rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF
    return C_RED if (r > b + 40 and r > g + 40) else C_NAVY


def build_logo_grid(opaque, W, bbox):
    x0, y0, x1, y1 = bbox
    lw, lh = x1 - x0 + 1, y1 - y0 + 1
    grid = [[0] * lw for _ in range(lh)]      # 0=透明 1=navy 2=red
    for a, rgb in opaque.items():
        grid[a // W - y0][a % W - x0] = 1 if classify(rgb) == C_NAVY else 2
    return grid, lw, lh


# ------------------------------------------------------------------ 2. osd_logo_rom.v
def gen_logo_rom(grid, lw, lh):
    L = []
    a = L.append
    a("// ============================================================================")
    a("// osd_logo_rom.v  ——  \"安路\" 标识位图 ROM（2bit/像素）")
    a("//   编码: 2'd0 = 透明, 2'd1 = 深蓝 #1C2D4E, 2'd2 = 红 #ED1C24")
    a("//   尺寸: %d x %d，地址 = ly*160 + lx（160 = 128+32，用移位加法，无乘法器）" % (lw, lh))
    a("//   数据来源: 安路官方 lab_ex3 例程 anlogic_logo_rom.v 的位图（主办方标识素材）")
    a("//   本文件为重新量化 + 重编码后的产物（24bit 多色/抗锯齿 -> 品牌两色 2bit），")
    a("//   由 tools/gen_osd_assets.py 自动生成，请勿手改。")
    a("// ============================================================================")
    a("")
    a("module osd_logo_rom (")
    a("    input  wire [13:0] I_addr,")
    a("    output reg  [1:0]  O_px")
    a(");")
    a("")
    a("    always @(*) begin")
    a("        case (I_addr)")
    n = 0
    for ly in range(lh):
        for lx in range(lw):
            v = grid[ly][lx]
            if v:
                a("            14'd%d: O_px = 2'd%d;" % (ly * LOGO_ROW_STRIDE + lx, v))
                n += 1
    a("            default: O_px = 2'd0;")
    a("        endcase")
    a("    end")
    a("")
    a("endmodule")
    print("  logo pixels encoded: %d / %d" % (n, lw * lh))
    return "\n".join(L) + "\n"


# ------------------------------------------------------------------ 3. 字模 / 文案
def gen_font_function():
    L = []
    a = L.append
    a("    // 5x7 点阵字模（自建，bit4 = 最左列）。case 键 = {字符码[6:0], 行号[2:0]} = 10bit。")
    a("    // 注意：字符码必须按 7bit 传（'A'=0x41 已经超过 6bit），否则键会被截断、字模串码。")
    a("    function [4:0] F_glyph;")
    a("        input [6:0] I_ch;")
    a("        input [2:0] I_row;")
    a("        begin")
    a("            case ({I_ch, I_row})")
    for ch in sorted(FONT, key=ord):
        for r in range(7):
            a("                10'h%03X: F_glyph = 5'b%s;  // '%s' row%d"
              % ((ord(ch) << 3) | r, format(FONT[ch][r], '05b'), ch if ch != ' ' else 'SP', r))
    a("                default: F_glyph = 5'b00000;")
    a("            endcase")
    a("        end")
    a("    endfunction")
    return "\n".join(L)


def gen_char_function():
    t0 = (TEXT0 + " " * CHAR_NUM)[:CHAR_NUM]
    t1 = (TEXT1 + " " * CHAR_NUM)[:CHAR_NUM]
    L = []
    a = L.append
    a("    // 两行文案（改字只改这里；不足 %d 字符用空格补齐，避免残留旧字）" % CHAR_NUM)
    a("    //   line0 = \"%s\"" % t0)
    a("    //   line1 = \"%s\"" % t1)
    a("    function [6:0] F_char;")
    a("        input [0:0] I_line;")
    a("        input [3:0] I_idx;")
    a("        begin")
    a("            case ({I_line, I_idx})")
    for li, txt in ((0, t0), (1, t1)):
        for i, ch in enumerate(txt):
            a("                5'h%02X: F_char = 7'h%02X;  // '%s'"
              % ((li << 4) | i, ord(ch), ch if ch != ' ' else 'SP'))
    a("                default: F_char = 7'h20;  // 空格")
    a("            endcase")
    a("        end")
    a("    endfunction")
    return "\n".join(L)


# ------------------------------------------------------------------ 4. 黄金模型
def render(x, y, grid, lw, lh):
    """返回 (rgb|None, kind)；kind ∈ none/plate/border/navy/red"""
    if not (PANEL_X <= x < PANEL_X + PANEL_W and PANEL_Y <= y < PANEL_Y + PANEL_H):
        return None, "none"
    if (x < PANEL_X + PANEL_BW or x >= PANEL_X + PANEL_W - PANEL_BW or
            y < PANEL_Y + PANEL_BW or y >= PANEL_Y + PANEL_H - PANEL_BW):
        return C_NAVY, "border"
    lx, ly = x - LOGO_X, y - LOGO_Y
    if 0 <= lx < lw and 0 <= ly < lh and grid[ly][lx]:
        return ((C_RED, "red") if grid[ly][lx] == 2 else (C_NAVY, "navy"))
    for li, y0 in ((0, TEXT_Y0), (1, TEXT_Y1)):
        if TEXT_X <= x < TEXT_X + CHAR_NUM * CHAR_ADV and y0 <= y < y0 + GLYPH_H:
            tx, ty = x - TEXT_X, y - y0
            ci, cx, cy = tx >> 4, tx & 15, ty >> 1
            if ci < CHAR_NUM and cx < 10 and cy < 7:
                txt = ((TEXT0 + " " * CHAR_NUM)[:CHAR_NUM] if li == 0
                       else (TEXT1 + " " * CHAR_NUM)[:CHAR_NUM])
                if (FONT.get(txt[ci], FONT[' '])[cy] >> (4 - (cx >> 1))) & 1:
                    return C_NAVY, "navy"
    return C_PLATE, "plate"


def scan(W, H, grid, lw, lh):
    """整帧遍历：分类计数 + 32bit 滚动哈希（h = h*33 + rgb，与 tb 中 (h<<5)+h+rgb 等价）"""
    cnt = {"plate": 0, "border": 0, "navy": 0, "red": 0}
    h = 0
    for y in range(H):
        for x in range(W):
            rgb, k = render(x, y, grid, lw, lh)
            if k != "none":
                cnt[k] += 1
            else:
                rgb = ((x & 0xFFF) << 12) | (y & 0xFFF)      # tb 里的测试图样
            h = ((h << 5) + h + rgb) & 0xFFFFFFFF
    return cnt, h


# ------------------------------------------------------------------ 5. PNG 预览
def write_png(path, w, h, rows):
    raw = b"".join(b"\x00" + bytes(r) for r in rows)

    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    open(path, "wb").write(png)


def build_preview(grid, lw, lh, path, W=1280, H=720):
    rows = []
    for y in range(H):
        row = bytearray()
        for x in range(W):
            # 合成“摄像头画面”：水平渐变 + 斜条纹；底部压暗，检验亮/暗背景下都能看清
            v = max(0, min(255, (x * 255) // (W - 1) + ((x + y) % 64) - 32))
            r = g = b = v
            if y > H * 3 // 4:
                r, g, b = 20, 20, 26
            rgb, _ = render(x, y, grid, lw, lh)
            if rgb is not None:
                r, g, b = (rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF
            row += bytes((r, g, b))
        rows.append(row)
    write_png(path, W, H, rows)
    print("  preview:", path)


# ------------------------------------------------------------------ main
def main():
    src = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_OFFICIAL_ROM
    if not os.path.isfile(src):
        raise SystemExit("找不到官方 ROM 源文件: %s\n用法: python gen_osd_assets.py <anlogic_logo_rom.v>" % src)

    opaque, W, bbox = load_logo(src)
    grid, lw, lh = build_logo_grid(opaque, W, bbox)
    print("logo bbox:", bbox, "=> size", lw, "x", lh, " opaque px:", len(opaque))

    os.makedirs(OUT_RTL, exist_ok=True)
    os.makedirs(OUT_TB, exist_ok=True)

    open(os.path.join(OUT_RTL, "osd_logo_rom.v"), "w", encoding="utf-8", newline="\n").write(
        gen_logo_rom(grid, lw, lh))
    print("  wrote rtl/osd_logo_rom.v")

    tpl = open(TPL, encoding="utf-8").read()
    body = (tpl.replace("//@@FONT@@", gen_font_function())
               .replace("//@@CHARS@@", gen_char_function())
               .replace("@@LOGO_W@@", str(lw))
               .replace("@@LOGO_H@@", str(lh)))
    open(os.path.join(OUT_RTL, "osd_overlay.v"), "w", encoding="utf-8", newline="\n").write(body)
    print("  wrote rtl/osd_overlay.v  (LOGO_W=%d LOGO_H=%d)" % (lw, lh))

    for w, h, tag in GEOMETRIES:
        cnt, hsh = scan(w, h, grid, lw, lh)
        print("  golden %s: %s  hash=%d" % (tag, cnt, hsh))
        lines = [
            "// ==== 由 tools/gen_osd_assets.py 生成，勿手改（帧 %dx%d）====" % (w, h),
            "    localparam integer EXP_PLATE  = %d;" % cnt["plate"],
            "    localparam integer EXP_BORDER = %d;" % cnt["border"],
            "    localparam integer EXP_NAVY   = %d;" % cnt["navy"],
            "    localparam integer EXP_RED    = %d;" % cnt["red"],
            "    localparam [31:0]  EXP_HASH   = 32'd%d;" % hsh,
            "",
        ]
        open(os.path.join(OUT_TB, "osd_tb_expect_%s.vh" % tag), "w",
             encoding="utf-8", newline="\n").write("\n".join(lines))
        print("  wrote tb/unit/osd_tb_expect_%s.vh" % tag)

    build_preview(grid, lw, lh, os.path.join(HERE, "osd_preview.png"))


if __name__ == "__main__":
    main()
