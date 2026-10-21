"""算法效果对比：官方固定阈值 Sobel vs 我们的自适应阈值 + 双阈值迟滞

目的：量化说明我们的算法在什么场景下更好、好多少（答辩素材 + 参数调优依据）

对比场景（合成图，真值已知）：
  1. 暗区低对比度边缘：灰度 20 -> 35（差 15），期望检出 1 条边缘
  2. 亮区低对比度边缘：灰度 200 -> 215（差 15），期望检出 1 条边缘
  3. 强边缘：灰度 50 -> 220，两者都应检出
  4. 平坦区 + 孤立噪点：灰度 128 + 稀疏 ±8 噪点，期望 0 条边缘

官方做法：灰度 -> Sobel(|Gx|+|Gy|) -> 固定阈值 80 -> 二值（无自适应、无迟滞）
我们做法：灰度 -> Sobel -> 自适应阈值 -> 因果双阈值迟滞
"""
import sys

import numpy as np

sys.path.insert(0, r"E:\fpga\contest_s2\sim\golden")
from edge_adaptive import process, sobel_and_mean, to_gray  # noqa: E402

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

W, H = 640, 360
OFFICIAL_THR = 80          # 官方 lab_ex2 的固定阈值


def official_edge(gray: np.ndarray, thr: int = OFFICIAL_THR) -> np.ndarray:
    """官方做法：固定阈值 80 判决，无迟滞"""
    mag, _ = sobel_and_mean(gray)
    return (mag >= thr).astype(np.uint8)


def make_scene(name: str):
    """生成测试场景，返回 (灰度图, 真值边缘图, 说明)"""
    g = np.full((H, W), 128, dtype=np.uint8)
    truth = np.zeros((H, W), dtype=np.uint8)
    if name == "dark_weak":            # 暗区低对比度竖直边缘（在列 320 处）
        g[:, :320] = 20
        g[:, 320:] = 35
        truth[:, 320] = 1
        desc = "暗区弱边缘 (20->35, 差15)"
    elif name == "bright_weak":        # 亮区低对比度竖直边缘
        g[:, :320] = 200
        g[:, 320:] = 215
        truth[:, 320] = 1
        desc = "亮区弱边缘 (200->215, 差15)"
    elif name == "strong":             # 强边缘
        g[:, :320] = 50
        g[:, 320:] = 220
        truth[:, 320] = 1
        desc = "强边缘 (50->220)"
    elif name == "flat_noise":         # 平坦 + 稀疏噪点
        rng = np.random.default_rng(7)
        mask = rng.random((H, W)) < 0.004
        noise = rng.integers(-8, 9, size=(H, W))
        g = np.clip(g.astype(np.int32) + np.where(mask, noise, 0), 0, 255).astype(np.uint8)
        desc = "平坦区+孤立噪点 (±8, 0.4%)"
    else:
        raise ValueError(name)
    return g, truth, desc


def gray_to_rgb(g: np.ndarray) -> np.ndarray:
    """灰度 -> RGB（仅用于复用 process()，三通道相同）"""
    return np.repeat(g[:, :, None], 3, axis=2)


def dilate(mask: np.ndarray, r: int = 2) -> np.ndarray:
    """真值边缘向左右膨胀 r 列：Sobel 在边缘两侧都会有响应，这属于正常宽度，不算误检"""
    out = mask.copy()
    for d in range(1, r + 1):
        out[:, d:] |= mask[:, :-d]
        out[:, :-d] |= mask[:, d:]
    return out


def stats(edge: np.ndarray, truth: np.ndarray):
    """统计命中 / 漏检 / 误检。

    只统计图像内部区域：边界 4 像素内受 padding 0 影响会产生假边缘（与算法无关），
    例如平坦 128 的图在最上 2 行会因顶部补 0 而出现 mag=512 的假边缘。
    """
    band = dilate(truth, 2)
    inner = np.zeros_like(edge, dtype=bool)
    inner[4:-4, 4:-4] = True
    e = (edge == 1) & inner
    hit = int((e & (band == 1)).sum())
    total_truth = int((truth == 1)[4:-4, 4:-4].sum())
    false_pos = int((e & (band == 0)).sum())
    missed = total_truth - int((e & (truth == 1)).sum())
    return hit, total_truth, false_pos, missed


def main() -> None:
    out_dir = r"E:\fpga\contest_s2\sim\golden\out"
    rows = []
    for name in ("dark_weak", "bright_weak", "strong", "flat_noise"):
        g, truth, desc = make_scene(name)
        rgb = gray_to_rgb(g)
        off_edge = official_edge(g)
        our_edge = process(rgb, k=2, floor=16)
        for tag, e in (("官方(固定80)", off_edge), ("我们(自适应)", our_edge)):
            hit, tot, fp, missed = stats(e, truth)
            rows.append((desc, tag, hit, tot, missed, fp, int(e.sum())))

    print(f"{'场景':<24}{'算法':<14}{'真边缘':<7}{'命中':<6}{'漏检':<6}{'平坦误检':<9}{'边缘总数'}")
    print("-" * 76)
    last = None
    for desc, tag, hit, tot, missed, fp, n in rows:
        print(f"{(desc if desc != last else ''):<24}{tag:<14}{tot:<7}{hit:<6}{missed:<6}{fp:<9}{n}")
        last = desc
        if tag.startswith("我们"):
            print()

        # 存图（左：灰度输入，中：官方，右：我们）
        try:
            from PIL import Image
            Image.fromarray(g, mode="L").save(f"{out_dir}\\cmp_{name}_in.png")
            Image.fromarray(off_edge * 255, mode="L").save(f"{out_dir}\\cmp_{name}_official.png")
            Image.fromarray(our_edge * 255, mode="L").save(f"{out_dir}\\cmp_{name}_ours.png")
        except ImportError:
            pass
        print()

    print("说明：'检出/真值' = 检出的真边缘数 / 真边缘总数；'误检' = 非边缘处被误判为边缘的像素数")
    print(f"输出图片目录：{out_dir}\\cmp_*.png")


if __name__ == "__main__":
    main()
