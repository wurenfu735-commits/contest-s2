# -*- coding: utf-8 -*-
"""黄金模型 v3：5×5 均值去噪 + 均值梯度 + 自适应阈值 + 因果迟滞
与 edge_adaptive_96.v v3 完全同构 —— 锚点、屏蔽、迟滞顺序逐条对齐。

窗口：10 列(4n-3..4n+6) × 7 行(y..y-6)；sum25 列和起点 0..5；三"中行"行组 r0..r4 / r2..r6。
mag = |S1-S2| + |S3-S4|；thr = FLOOR + ((mean25*K)>>5)，mean25 = s25>>4（近似 /16）。
判决锚点：像素 (4n+i, y-3)。屏蔽：row_ok y>=8；n==0 mask i<=2；末组 mask i>=2。
"""
import sys
W, H = 128, 12      # 高度 12：冷启动 6 行 + row_ok>=8 后仍有 4 个可比行
GRP = W // 4
FLOOR, K = 16, 2

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

img = [[0] * W for _ in range(H)]
for y in range(H):
    for x in range(W):
        img[y][x] = gray(x, y)

def gr(y, x):
    if 0 <= y < H and 0 <= x < W:
        return img[y][x]
    return 0

E = [[[0] * 4 for _ in range(GRP)] for _ in range(H)]

for y in range(H):
    for n in range(GRP):
        x0 = 4 * n - 3
        # 每行 10 列窗口，列和起点 0..5（5 列滑动和）
        rows = []
        for dy in range(7):  # r0=y .. r6=y-6
            w = [gr(y - dy, x0 + k) if (y - dy) >= 0 else 0 for k in range(10)]
            col5 = [sum(w[k:k + 5]) for k in range(6)]
            rows.append(col5)

        for i in range(4):
            S1 = rows[0][i + 2] + rows[1][i + 2] + rows[2][i + 2] + rows[3][i + 2] + rows[4][i + 2]
            S2 = rows[0][i] + rows[1][i] + rows[2][i] + rows[3][i] + rows[4][i]
            S3 = rows[0][i + 1] + rows[1][i + 1] + rows[2][i + 1] + rows[3][i + 1] + rows[4][i + 1]
            S4 = rows[2][i + 1] + rows[3][i + 1] + rows[4][i + 1] + rows[5][i + 1] + rows[6][i + 1]

            mag = abs(S1 - S2) + abs(S3 - S4)
            mean25 = S3 >> 4          # 近似 /16（与 RTL 一致）
            thr = FLOOR + ((mean25 * K) >> 5)

            strong = mag >= thr
            weak = mag >= (thr >> 1)

            up = E[y - 1][n] if y - 1 >= 0 else [0, 0, 0, 0]
            up_prev = E[y - 1][n - 1] if (y - 1 >= 0 and n - 1 >= 0) else [0, 0, 0, 0]
            u0 = up_prev[3] if i == 0 else up[i - 1]
            left = E[y][n][i - 1] if i > 0 else (E[y][n - 1][3] if n > 0 else 0)

            e = strong or (weak and (left or up[i] or u0))

            if y < 8:
                e = 0
            if n == 0 and i <= 2:
                e = 0
            if n == GRP - 1 and i >= 2:
                e = 0
            E[y][n][i] = 1 if e else 0

lines = []
for y in range(H):
    for n in range(GRP):
        base = y * W + 4 * n
        bits = E[y][n]
        lines.append("%d %d %d %d %d" % (base, bits[0], bits[1], bits[2], bits[3]))
open(r"E:\fpga\contest_s2\sim\tb96\golden_out.txt", "w").write("\n".join(lines) + "\n")
print("golden v3 写出 %d 组 (H=%d)" % (len(lines), H))