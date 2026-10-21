"""暗区阈值扫描 —— 复现 edge_adaptive_96 v4 的判决数学，量化"暗区地板"该怎么定

目的：用户反馈"稍微暗一点的环境容易检测不出来"。本脚本用与 RTL 完全一致的
算子结构，在合成场景上扫描暗区地板取值，输出 检出率(TPR) 与 虚警率(FPR)，
用来回答"192 是不是太高、降到多少合适"。

算子复现（与 edge_adaptive_96.v 对齐）：
  S1/S2/S3/S4 均为 5×5 求和，中心坐标：
      S1 = (y-2, p+1)   S2 = (y-2, p-1)   S3 = (y-2, p)   S4 = (y-4, p)
  mag = |S1-S2| + |S3-S4|
  m25 = S3 >> 4
  thr = section_floor(m25) + ((m25 * K) >> 5)
  strong = mag >= thr ;  weak = mag >= (thr >> 1)
  e = strong | (weak & left_in)      # 因果迟滞

用法：
  python tools/analyze_dark_threshold.py
"""

import numpy as np

K = 2                    # 与 isp_top / tb 一致
THR_FLOOR = 96           # v4 基准地板
SHAPE = (64, 128)        # H, W
EDGE_X = 64              # 竖直阶跃位置


def box5(img):
    """5×5 求和（边界用 edge padding，避免影响中间区域）"""
    from numpy.lib.stride_tricks import sliding_window_view
    pad = np.pad(img.astype(np.int64), 2, mode="edge")
    win = sliding_window_view(pad, (5, 5))
    return win.sum(axis=(2, 3))


def center_shift(b, dy, dx):
    """把 box 结果按中心点 (y-2, p) 平移到 (y-2+dy, p+dx) 的对齐，返回与 b 同形状的数组"""
    out = np.zeros_like(b)
    H, W = b.shape
    ys = slice(max(0, -dy), H - max(0, dy))
    xs = slice(max(0, -dx), W - max(0, dx))
    ys2 = slice(max(0, dy), H - max(0, -dy))
    xs2 = slice(max(0, dx), W - max(0, -dx))
    out[ys, xs] = b[ys2, xs2]
    return out


def edge_mag(img):
    """返回与 img 同尺寸的 mag（像素 (y,p) 对应 5×5 窗口中心 y-2）"""
    b = box5(img)
    S3 = b
    S1 = center_shift(b, 0, +1)
    S2 = center_shift(b, 0, -1)
    S4 = center_shift(b, -2, 0)
    return np.abs(S1 - S2) + np.abs(S3 - S4), S3


def section_floor(m25, dark_extra_of, bright_floor=THR_FLOOR):
    """dark_extra_of: 函数 step_index(0..3) -> 加在地板上的量，step0=最暗"""
    f = np.empty_like(m25)
    f[m25 < 64] = bright_floor + dark_extra_of(0)
    f[(m25 >= 64) & (m25 < 128)] = bright_floor + dark_extra_of(1)
    f[(m25 >= 128) & (m25 < 192)] = bright_floor + dark_extra_of(2)
    f[m25 >= 192] = bright_floor + dark_extra_of(3)
    return f


def detect(img, extras):
    """逐像素因果迟滞，与黄金模型同构：
         e = strong | (weak & (左邻e | 上邻e | 左上邻e))
       注意必须用"已判决的 e"做传播，不能用 weak —— 没有强边种子时整条弱边不该点亮。
    """
    mag, S3 = edge_mag(img)
    m25 = S3 >> 4
    thr = section_floor(m25, lambda i: extras[i]) + ((m25 * K) >> 5)
    strong = mag >= thr
    weak = mag >= (thr >> 1)
    H, W = mag.shape
    E = np.zeros((H, W), dtype=bool)
    for y in range(H):
        prev = E[y - 1] if y > 0 else np.zeros(W, dtype=bool)
        row = E[y]
        for p in range(W):
            if strong[y, p]:
                row[p] = True
            elif weak[y, p]:
                left = row[p - 1] if p > 0 else False
                ul = prev[p - 1] if p > 0 else False
                row[p] = left or prev[p] or ul
    return E


def make_scene(level, contrast, sigma, shape=SHAPE, edge_x=EDGE_X, seed=0):
    """左暗右亮的竖直阶跃 + 高斯噪声"""
    rng = np.random.default_rng(seed)
    H, W = shape
    img = np.full(shape, level, dtype=np.float64)
    img[:, edge_x:] = level + contrast
    img += rng.normal(0, sigma, shape)
    return np.clip(np.round(img), 0, 255).astype(np.int64)


def score(e, edge_x=EDGE_X, shape=SHAPE):
    """TPR：边缘带 |p-edge_x|<=1 的检出比例；FPR：远离边缘的平坦区误检比例"""
    H, W = shape
    band = (slice(8, H - 8), slice(edge_x - 1, edge_x + 2))
    flat = (slice(8, H - 8), np.r_[12:edge_x - 12, edge_x + 12:W - 12])
    tpr = e[band].mean()
    fpr = e[flat].mean()
    return tpr, fpr


def eval_avg(extras, level, contrast, sigma, n=12):
    """多随机种子平均，消除单次采样抖动"""
    tp = fp = 0.0
    for s in range(n):
        img = make_scene(level, contrast, sigma, seed=1000 + s)
        tpr, fpr = score(detect(img, extras))
        tp += tpr
        fp += fpr
    return tp / n, fp / n


def main():
    print("=" * 78)
    print("A) 先验算：mag 与阶跃幅度 Δ 的关系（无噪声，竖直边）")
    print("   竖直阶跃只有水平项 |S1-S2| 贡献，故 mag = 10×Δ（每行 2×Δ，5 行累加）")
    print("=" * 78)
    for d in (4, 8, 10, 20):
        img = make_scene(40, d, 0.0)
        mag, _ = edge_mag(img)
        peak = mag[20:40, EDGE_X - 1:EDGE_X + 2].max()
        print(f"  Δ={d:3d}  →  mag 峰值 = {peak:5d}   (10×Δ = {10 * d})")

    print()
    print("=" * 78)
    print("B) 暗区地板扫描（暗场 mean≈32，σ=4；12 个随机种子平均）")
    print("=" * 78)
    print("  暗区地板  暗Δ=6   暗Δ=8   暗Δ=10  暗Δ=12 | 暗场平坦FPR")
    print("  " + "-" * 56)
    for e0 in (96, 80, 64, 48, 32, 16, 0):
        extras = (e0, 64, 32, 0)
        row = [eval_avg(extras, 32, d, 4.0)[0] for d in (6, 8, 10, 12)]
        _, fpr = eval_avg(extras, 32, 0, 4.0)
        mark = "  ← v4 现状" if e0 == 96 else ""
        print(f"  {THR_FLOOR + e0:5d}    "
              f"{row[0]:6.1%} {row[1]:6.1%} {row[2]:6.1%} {row[3]:6.1%} |"
              f"   {fpr:8.2%}{mark}")

    print()
    print("=" * 78)
    print("C) 噪声敏感度：暗场 Δ=10 的 TPR / 平坦区 FPR（12 种子平均）")
    print("=" * 78)
    print("  σ\\地板    192        160        144        128        112")
    print("  " + "-" * 70)
    for sigma in (2.0, 3.0, 4.0, 6.0, 8.0):
        cells = []
        for e0 in (96, 64, 48, 32, 16):
            extras = (e0, 64, 32, 0)
            tpr, _ = eval_avg(extras, 32, 10, sigma)
            _, fpr = eval_avg(extras, 32, 0, sigma)
            cells.append(f"{tpr:5.1%}/{fpr:5.2%}")
        print(f"  {sigma:4.1f}   " + "  ".join(cells))

    print()
    print("=" * 78)
    print("D) 候选曲线对比（e0..e3，基准 THR_FLOOR=96；12 种子平均）")
    print("=" * 78)
    curves = {
        "v4 现状 192/160/128/96": (96, 64, 32, 0),
        "A       160/144/128/96": (64, 48, 32, 0),
        "B       160/136/116/96": (64, 40, 20, 0),
        "C       144/132/116/96": (48, 36, 20, 0),
        "D       128/120/108/96": (32, 24, 12, 0),
    }
    print(f"  {'曲线':24s} {'σ4 Δ8':>7s} {'σ4 FPR':>8s} {'σ6 Δ8':>7s} {'σ6 FPR':>8s} {'σ4 亮Δ8':>9s}")
    print("  " + "-" * 72)
    for name, extras in curves.items():
        r4 = eval_avg(extras, 32, 8, 4.0)
        r6 = eval_avg(extras, 32, 8, 6.0)
        rb = eval_avg(extras, 176, 8, 2.0)
        print(f"  {name:24s} {r4[0]:6.1%} {r4[1]:8.2%} {r6[0]:6.1%} {r6[1]:8.2%} {rb[0]:8.1%}")


if __name__ == "__main__":
    main()
