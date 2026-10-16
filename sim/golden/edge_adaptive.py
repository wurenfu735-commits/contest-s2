"""P2 自适应阈值边缘检测 · Python 黄金模型

作用：
  1. 按《P2 算法规格》生成"标准答案"边缘图，供 ModelSim 与 RTL 逐像素比对
  2. 快速试参数（阈值下限 THR_FLOOR、亮度灵敏度 K），看视觉效果
  3. 生成与 RTL 一致的测试图（复刻 test_pattern_gen.v 的 4 种图案）

关键设计：本模型严格按 RTL 的"流式因果"顺序实现——
  每个输出像素只依赖当前像素与已扫描过的邻域（左、上、左上），
  不使用任何未来像素。这样黄金模型与 RTL 才能做到逐像素 0 误差。

用法：
  python edge_adaptive.py --all                       # 4 种图案全跑
  python edge_adaptive.py --pattern colorbar          # 只跑彩条
  python edge_adaptive.py --pattern colorbar --k 3 --floor 24
  python edge_adaptive.py --all --ideal               # 额外输出"理想迟滞"版做对照

口径说明（2026-10-17 标注）：本文件是 v1–v3 时期的黄金模型（3×3 均值、默认 FLOOR=16），
已不在现行一键验证链路里（run_tb_96.ps1 走的是仓库顶层 tools/gen_golden_v4.py）；
保留它是为了参数试跑与图案对照。现行 v4 口径（5×5 均值 + 分段 FLOOR，基准 96）
以 tools/gen_golden_v4.py 与 src/p1_colorbar/rtl/edge_adaptive_96.v 为准。
"""

import argparse
import os
import sys

import numpy as np

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# ---------- 与 RTL 一致的默认参数 ----------
IMG_W, IMG_H = 1280, 720
DEFAULT_FLOOR = 16          # 阈值下限（RTL: THR_FLOOR）
DEFAULT_K = 2               # 亮度灵敏度档（RTL: 用移位实现）
K_SHIFT = 5                 # thr = FLOOR + ((mean9 * K) >> 5)


# ============================================================
# 1. 测试图生成（复刻 rtl/test_pattern_gen.v）
# ============================================================
def gen_pattern(sel: int, w: int = IMG_W, h: int = IMG_H) -> np.ndarray:
    """生成与 RTL 一致的测试图，返回 (h, w, 3) uint8 RGB。"""
    img = np.zeros((h, w, 3), dtype=np.uint8)
    xs = np.arange(w)
    ys = np.arange(h)
    xx, yy = np.meshgrid(xs, ys)

    if sel == 0:      # 八色彩条：每段 160 列
        colors = [(255, 255, 255), (255, 255, 0), (0, 255, 255), (0, 255, 0),
                  (255, 0, 255), (255, 0, 0), (0, 0, 255), (0, 0, 0)]
        seg = w // 8
        for i, c in enumerate(colors):
            img[:, i * seg:(i + 1) * seg] = c

    elif sel == 1:    # 16×16 棋盘格
        cell = 16
        checker = ((xx // cell) + (yy // cell)) % 2
        img[checker == 0] = (255, 255, 255)
        img[checker == 1] = (0, 0, 0)

    elif sel == 2:    # 渐变：R 水平、G 垂直、B 反向水平
        img[..., 0] = (xx * 255 // max(1, w - 1)).astype(np.uint8)
        img[..., 1] = (yy * 255 // max(1, h - 1)).astype(np.uint8)
        img[..., 2] = (255 - xx * 255 // max(1, w - 1)).astype(np.uint8)

    else:             # 八级灰阶，每段 160 列
        seg = w // 8
        for i in range(8):
            v = i * 255 // 7
            img[:, i * seg:(i + 1) * seg] = (v, v, v)

    return img


# ============================================================
# 2. 算法（与 RTL 逐位一致）
# ============================================================
def to_gray(rgb: np.ndarray) -> np.ndarray:
    """R/4 + G/2 + B/4（与 RTL 的移位写法一致，无溢出，范围 0..253）"""
    r = rgb[..., 0].astype(np.uint16) >> 2
    g = rgb[..., 1].astype(np.uint16) >> 1
    b = rgb[..., 2].astype(np.uint16) >> 2
    return (r + g + b).astype(np.uint16)


def sobel_and_mean(gray: np.ndarray):
    """3×3 Sobel 梯度 |Gx|+|Gy| 与 3×3 邻域和。

    窗口的垂直顺序与 RTL 的流式时间顺序严格一致：
        p00 行 = y-2（上上行）、p10 行 = y-1（上一行）、p20 行 = y（当前行）
    因此只在顶部补 2 行 0，底部不补——RTL 是因果的，不使用未来行。
    （若按"以 y 为中心"补 0，最后一行会把下方当成全黑而产生假边缘）
    """
    p = np.pad(gray.astype(np.int32), ((2, 0), (1, 1)), mode="constant", constant_values=0)
    p00 = p[0:-2, 0:-2]; p01 = p[0:-2, 1:-1]; p02 = p[0:-2, 2:]
    p10 = p[1:-1, 0:-2]; p11 = p[1:-1, 1:-1]; p12 = p[1:-1, 2:]
    p20 = p[2:,   0:-2]; p21 = p[2:,   1:-1]; p22 = p[2:,   2:]

    gx = -p00 + p02 - 2 * p10 + 2 * p12 - p20 + p22
    gy = p00 + 2 * p01 + p02 - p20 - 2 * p21 - p22
    mag = np.abs(gx) + np.abs(gy)

    sum9 = p00 + p01 + p02 + p10 + p11 + p12 + p20 + p21 + p22
    return mag, sum9


def threshold_map(sum9: np.ndarray, k: int, floor: int) -> np.ndarray:
    """自适应阈值：thr = floor + ((mean9 * k) >> K_SHIFT)，mean9 = sum9 >> 3"""
    mean9 = sum9 >> 3
    thr = floor + ((mean9 * k) >> K_SHIFT)
    return thr


def hysteresis_causal(mag: np.ndarray, thr: np.ndarray) -> np.ndarray:
    """双阈值迟滞（流式因果版，与 RTL 完全同序）

    - mag >= thr_high            -> 强边缘
    - thr_low <= mag < thr_high  -> 仅当左/上/左上已被判为边缘时保留
    - mag < thr_low              -> 非边缘
    扫描顺序：逐行、行内从左到右（与视频流一致）
    """
    h, w = mag.shape
    out = np.zeros((h, w), dtype=np.uint8)
    thr_low = thr >> 1

    for y in range(h):
        row_mag = mag[y]
        row_thr = thr[y]
        row_out = out[y]
        prev_out = out[y - 1] if y > 0 else None
        for x in range(w):
            m = row_mag[x]
            if m >= row_thr[x]:
                row_out[x] = 1
            elif m >= thr_low[y, x]:
                keep = 0
                if x > 0 and row_out[x - 1]:
                    keep = 1
                elif prev_out is not None and prev_out[x]:
                    keep = 1
                elif x > 0 and prev_out is not None and prev_out[x - 1]:
                    keep = 1
                row_out[x] = keep
    return out


def hysteresis_ideal(mag: np.ndarray, thr: np.ndarray) -> np.ndarray:
    """理想迟滞（全图连通性，仅作效果上限对照，RTL 无法实现）"""
    thr_low = thr >> 1
    strong = mag >= thr
    weak = (mag >= thr_low) & (~strong)
    out = strong.copy()
    # 迭代传播：弱边缘只要与强边缘 8 邻域连通就保留
    for _ in range(64):
        grown = out.copy()
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                shifted = np.roll(np.roll(out, dy, axis=0), dx, axis=1)
                grown |= shifted & weak
        if np.array_equal(grown, out):
            break
        out = grown
    return out.astype(np.uint8)


def process(rgb: np.ndarray, k: int = DEFAULT_K, floor: int = DEFAULT_FLOOR,
            ideal: bool = False) -> np.ndarray:
    """完整算法流水线，返回边缘图 (h, w) uint8，取值 0/1"""
    gray = to_gray(rgb)
    mag, sum9 = sobel_and_mean(gray)
    thr = threshold_map(sum9, k, floor)
    if ideal:
        return hysteresis_ideal(mag, thr)
    edge = hysteresis_causal(mag, thr)
    # 边界规则与 RTL 的 win_valid 严格一致：
    # 前 2 行没有上上行数据；行首第 0 列凑不齐左边界 -> 输出 0
    edge[:2, :] = 0
    edge[:, :1] = 0
    return edge


# ============================================================
# 3. 输出工具
# ============================================================
def save_png(arr01: np.ndarray, path: str) -> None:
    """把 0/1 边缘图存成黑白 PNG（供人眼检查）；无 PIL 时退回 PGM"""
    try:
        from PIL import Image
        img = (arr01.astype(np.uint8) * 255)
        Image.fromarray(img, mode="L").save(path)
        return
    except ImportError:
        pass
    pgm = os.path.splitext(path)[0] + ".pgm"
    h, w = arr01.shape
    with open(pgm, "wb") as f:
        f.write(f"P5\n{w} {h}\n255\n".encode())
        f.write((arr01.astype(np.uint8) * 255).tobytes())


def save_raw(arr01: np.ndarray, path: str) -> None:
    """存成 RTL testbench 可直接读的原始字节（1 字节/像素，0 或 255）"""
    with open(path, "wb") as f:
        f.write((arr01.astype(np.uint8) * 255).tobytes())


def save_txt(arr: np.ndarray, path: str, hexdigits: int = 1) -> None:
    """导出文本向量（每行一个十六进制数）供 ModelSim $readmemh 读取。

    gray_*.txt = 输入灰度（2 位十六进制），edge_*.txt = 期望边缘（1 位）
    """
    flat = arr.astype(np.uint16).ravel()
    with open(path, "w", encoding="ascii", newline="\n") as f:
        for v in flat:
            f.write(format(int(v), "0{}x".format(hexdigits)) + "\n")


def save_rgb_png(rgb: np.ndarray, path: str) -> None:
    try:
        from PIL import Image
        Image.fromarray(rgb, mode="RGB").save(path)
    except ImportError:
        print(f"  (无 PIL，跳过 {path})")


# ============================================================
# 4. 主流程
# ============================================================
PATTERNS = {0: "colorbar", 1: "checker", 2: "gradient", 3: "gray8"}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pattern", default=None, help="colorbar/checker/gradient/gray8")
    ap.add_argument("--all", action="store_true", help="4 种图案全跑")
    ap.add_argument("--k", type=int, default=DEFAULT_K, help="亮度灵敏度档 0..3")
    ap.add_argument("--floor", type=int, default=DEFAULT_FLOOR, help="阈值下限")
    ap.add_argument("--ideal", action="store_true", help="额外输出理想迟滞版（对照用）")
    ap.add_argument("--out", default=r"E:\fpga\contest_s2\sim\golden\out")
    ap.add_argument("--w", type=int, default=IMG_W)
    ap.add_argument("--h", type=int, default=IMG_H)
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    if args.all:
        sels = list(PATTERNS.keys())
    elif args.pattern:
        sels = [k for k, v in PATTERNS.items() if v == args.pattern]
        if not sels:
            print("未知图案，可选:", ", ".join(PATTERNS.values()))
            return
    else:
        sels = [0]

    print(f"参数: K={args.k}  FLOOR={args.floor}  尺寸={args.w}x{args.h}  ideal={args.ideal}")
    for sel in sels:
        name = PATTERNS[sel]
        rgb = gen_pattern(sel, args.w, args.h)
        edge = process(rgb, k=args.k, floor=args.floor)
        ratio = edge.mean() * 100

        save_rgb_png(rgb, os.path.join(args.out, f"in_{name}.png"))
        save_png(edge, os.path.join(args.out, f"edge_{name}.png"))
        save_raw(edge, os.path.join(args.out, f"edge_{name}.raw"))
        # RTL 比对用文本向量：输入灰度 + 期望边缘（ModelSim $readmemh 读）
        save_txt(to_gray(rgb), os.path.join(args.out, f"gray_{name}.txt"), 2)
        save_txt(edge, os.path.join(args.out, f"edge_{name}.txt"), 1)
        # 中间结果（mag/thr）供差异定位
        _mag, _sum9 = sobel_and_mean(to_gray(rgb))
        _thr = threshold_map(_sum9, args.k, args.floor)
        _mag[:2, :] = 0
        _thr[:2, :] = 0
        save_txt(_mag, os.path.join(args.out, f"mag_{name}.txt"), 3)
        save_txt(_thr, os.path.join(args.out, f"thr_{name}.txt"), 3)
        print(f"  [{name}] 边缘像素占比 {ratio:5.2f}%  -> edge/gray/mag/thr 四组向量")

        if args.ideal:
            edge_i = process(rgb, k=args.k, floor=args.floor, ideal=True)
            save_png(edge_i, os.path.join(args.out, f"edgeIdeal_{name}.png"))
            print(f"  [{name}] 理想迟滞版占比 {edge_i.mean()*100:5.2f}%  -> edgeIdeal_{name}.png")

    print("完成，输出目录:", args.out)


if __name__ == "__main__":
    main()
