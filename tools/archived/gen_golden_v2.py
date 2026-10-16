# -*- coding: utf-8 -*-
"""黄金模型 v2：3×3 均值去噪 + 均值梯度 + 自适应阈值 + 因果迟滞
与 edge_adaptive_96.v (v2) 完全同构 —— 锚点、屏蔽、迟滞顺序逐条对齐。
输出 par 期望文件，与 tb 的 par_out.txt 逐像素比对。
"""
import sys
W, H = 128, 8
GRP = W // 4
FLOOR, K, OFF = 16, 2, 60
MODE = 2

def noisy(v, x, y):
    s = v + (((x & 0xF) * 13 + ((x & 0x7F) ^ (y & 0x7F)) * 31 + (y & 0x7F) * 7) & 0xF) - 8
    return max(0, min(255, s))

def v0(x, y):
    if ((x >> 4) ^ (y >> 3)) & 1 == 0:
        v = 120 + (x & 7)
    else:
        v = 40
    if (x >> 5) & 0x3 == 2:
        v = 200
    return v

def gray(x, y):
    a = noisy(v0(x, y), x, y)
    return (a >> 2) + (a >> 1) + (a >> 2)

# grayscale image
img = [[gray(x, y) for x in range(W)] for y in range(H)]

def gr(y, x):  # 越界返回 0（比较区域用不到）
    if 0 <= y < H and 0 <= x < W:
        return img[y][x]
    return 0

# 逐行逐组计算，锚点与 RTL 相同：判决像素 = (列 4n+i, 行 y-2)
# RTL 时序：拍 m 窗口 b=行 y(当拍), m=y-1, t=y-2, q=y-3；x_d2(m)=n；判决锚行标 y_d2
# 简化：直接对"处理时刻"用 b=y 的输入行集合
E = [[[0] * 4 for _ in range(GRP)] for _ in range(H)]   # E[y][n][i]

for y in range(H):
    for n in range(GRP):
        # 窗口 w[0..7] = 行 r 的列 4n-2 .. 4n+5
        def row_w(r):
            x0 = 4 * n - 2
            return [gr(r, x0 + k) for k in range(8)]

        bw = row_w(y)
        mw = row_w(y - 1)
        tw = row_w(y - 2)
        qw = row_w(y - 3)

        def c3(w, i):
            return w[i] + w[i + 1] + w[i + 2]

        for i in range(4):
            t3_ = [c3(tw, k) for k in range(6)]
            m3_ = [c3(mw, k) for k in range(6)]
            b3_ = [c3(bw, k) for k in range(6)]
            q3_ = [c3(qw, k) for k in range(6)]

            S1 = t3_[i + 2] + m3_[i + 2] + b3_[i + 2]
            S2 = t3_[i] + m3_[i] + b3_[i]
            S3 = t3_[i + 1] + m3_[i + 1] + b3_[i + 1]
            S4 = q3_[i + 1] + t3_[i + 1] + m3_[i + 1]

            mag = abs(S1 - S2) + abs(S3 - S4)
            mean9 = S3 >> 3
            mk = mean9 * K
            thr = FLOOR + (mk >> 5)

            strong = mag >= thr
            weak = mag >= (thr >> 1)

            up = E[y - 1][n] if y - 1 >= 0 else [0, 0, 0, 0]
            up_prev = E[y - 1][n - 1] if (y - 1 >= 0 and n - 1 >= 0) else [0, 0, 0, 0]
            u0 = up_prev[3] if i == 0 else up[i - 1]

            left = E[y][n][i - 1] if i > 0 else (E[y][n - 1][3] if n > 0 else 0)
            nbr = (left, up[i], u0)
            e = strong or (weak and (left or up[i] or u0))

            # 边界屏蔽（对齐 RTL v2）
            row_ok = y >= 5
            grp0 = (n == 0)
            last = (n == GRP - 1)
            if not row_ok:
                e = 0
            if grp0 and i <= 1:
                e = 0
            if last and i >= 2:
                e = 0
            E[y][n][i] = 1 if e else 0

# 输出（与 tb 的 par_out.txt 同格式：像素编号 + 4 判决）
lines = []
for y in range(H):
    for n in range(GRP):
        base = (y * W) + 4 * n
        bits = E[y][n]
        lines.append("%d %d %d %d %d" % (base, bits[0], bits[1], bits[2], bits[3]))
open(r"E:\fpga\contest_s2\sim\tb96\golden_out.txt", "w").write("\n".join(lines) + "\n")
print("golden 写出 %d 组" % len(lines))