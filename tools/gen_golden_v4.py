# -*- coding: utf-8 -*-
"""黄金模型 v4：分段 FLOOR（噪声-亮度联合自适应）+ 5×5 均值梯度 + 因果迟滞
与 edge_adaptive_96.v v4 完全同构（锚点/屏蔽/迟滞顺序逐条对齐）。

v4 阈值：thr = FLOOR_section(mean25) + ((mean25*K)>>5)
  mean25 = s25 >> 4（≈ /16）
  分段（保守物理初值，见 MEMORY v4 阶段记录；分段点换算回画面灰度见注释）：
    mean25 <  64         → FLOOR=192   （画面灰度 <41，暗：压噪优先）
    64  ≤ mean25 < 128   → FLOOR=160   （灰度 41-82）
    128 ≤ mean25 < 192   → FLOOR=128   （灰度 82-123）
    mean25 ≥ 192         → FLOOR=96    （灰度 ≥123，亮：保细节）
  物理依据：散粒噪声随亮度上升、信噪比随亮度改善 → 地板随亮度单调下降。

本脚本同时跑两个场景并输出指标：
  场景A 噪声图案（±8 均匀噪声）：暗区平坦块"假边缘比例"（应大幅低于 v3）
  场景B 低对比图案（台阶14、亮背景，近似 TPG 图案4/5/6）：边缘检出（应保住）
"""
import sys
W, H = 128, 12
GRP = W // 4
K = 2

def section_floor(mean25):
    if mean25 < 64:  return 192
    if mean25 < 128: return 160
    if mean25 < 192: return 128
    return 96

# ---------- 场景 A：噪声图案（原有，亮区锯齿 + 暗区 + 高亮段 + ±8 噪声）----------
def noisy(v, x, y):
    s = v + (((x & 0xF) * 13 + ((x & 0xFF) ^ (y & 0xFF)) * 31 + (y & 0xFF) * 7) & 7) - 3   # 与 tb 逐字一致
    return max(0, min(255, s))

def v0(x, y):
    # 行向恒定：x[4]=0 亮区锯齿（含弱边缘）、x[4]=1 暗区；64-95 高亮段
    v = (120 + (x & 7)) if ((x >> 4) & 1) == 0 else 40
    if (x >> 5) & 0x3 == 2:
        v = 200
    return v

def gray_a(x, y):
    a = noisy(v0(x, y), x, y)
    return (a >> 2) + (a >> 1) + (a >> 2)

# ---------- 场景 B：低对比图案（亮背景 120，台阶 14 的竖条纹，无噪声）----------
def gray_b(x, y):
    return 120 + (14 if ((x >> 3) & 1) else 0)

def run(img, fname):
    E = [[[0] * 4 for _ in range(GRP)] for _ in range(H)]
    for y in range(H):
        for n in range(GRP):
            x0 = 4 * n - 3
            rows = []
            for dy in range(7):
                w = [img(x0 + k, y - dy) if (y - dy) >= 0 else 0 for k in range(10)]
                rows.append([sum(w[k:k + 5]) for k in range(6)])
            for i in range(4):
                S1 = sum(rows[d][i + 2] for d in range(5))
                S2 = sum(rows[d][i] for d in range(5))
                S3 = sum(rows[d][i + 1] for d in range(5))
                S4 = sum(rows[d][i + 1] for d in range(2, 7))
                mag = abs(S1 - S2) + abs(S3 - S4)
                mean25 = S3 >> 4
                thr = section_floor(mean25) + ((mean25 * K) >> 5)
                strong = mag >= thr
                weak = mag >= (thr >> 1)
                up = E[y - 1][n] if y - 1 >= 0 else [0, 0, 0, 0]
                up_prev = E[y - 1][n - 1] if (y - 1 >= 0 and n - 1 >= 0) else [0, 0, 0, 0]
                u0 = up_prev[3] if i == 0 else up[i - 1]
                left = E[y][n][i - 1] if i > 0 else (E[y][n - 1][3] if n > 0 else 0)
                e = strong or (weak and (left or up[i] or u0))
                if y < 8: e = 0
                if n == 0 and i <= 2: e = 0
                if n == GRP - 1 and i >= 2: e = 0
                E[y][n][i] = 1 if e else 0
    # 输出 par 格式（供 RTL 对标用）
    with open(r"E:\fpga\contest_s2\sim\tb96\golden_out.txt", "w") as f:
        for y in range(H):
            for n in range(GRP):
                f.write("%d %d %d %d %d\n" % (y * W + 4 * n, *E[y][n]))
    return E

Ea = run(gray_a, "A")
# 场景 A 指标（严格口径：窗口所需列 [c-3..c+6] 全部在同一暗段且非高亮段）
fp_flat = 0; tot_flat = 0
for y in range(8, H):
    for n in range(1, GRP - 1):
        for i in range(4):
            c = 4 * n + i
            if 12 <= c <= 115:
                if all(v0(xx, y) == 40 for xx in range(c - 3, c + 7)):
                    tot_flat += 1
                    fp_flat += Ea[y][n][i]
print("场景A(严格纯暗区) %d 个，假边缘 %d 个，比例 %.1f%%" % (tot_flat, fp_flat, 100.0 * fp_flat / max(1, tot_flat)))

# 场景 B 指标
Eb = run(gray_b, "B")
edge_hit = 0
for y in range(8, H):
    for n in range(1, GRP - 1):
        for i in range(4):
            c = 4 * n + i
            if 12 <= c <= 115 and (c % 16) in (7, 8):
                edge_hit += Eb[y][n][i]
print("场景B 低对比(台阶14)图案：边缘位置 %d 个，检出 %d 个，比例 %.1f%%" % ((H - 8) * 2 * ((115-12)//16 + 1), edge_hit, 100.0 * edge_hit / max(1, (H - 8) * 2 * 7)))
# golden_out 用场景 A 图案重新生成（与 tb 同图案，供 RTL 对标）
run(gray_a, "A-final")
print("golden v4 已写出（场景A 版本，供 RTL 对标）")