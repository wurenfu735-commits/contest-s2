# -*- coding: utf-8 -*-
"""debug：打印 v4 模型中一个纯暗区像素的 S/mag/thr/E，核实假边缘从哪来"""
W, H = 128, 12
GRP = W // 4
K = 2

def section_floor(mean25):
    if mean25 < 64: return 192
    if mean25 < 128: return 160
    if mean25 < 192: return 128
    return 96

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

def gray_a(x, y):
    a = noisy(v0(x, y), x, y)
    return (a >> 2) + (a >> 1) + (a >> 2)

# 取纯暗区中间像素 c=20（窗口 17..26 全暗）
y, c = 10, 20
n, i = c // 4, c % 4
x0 = 4 * n - 3
print("y=%d c=%d n=%d i=%d" % (y, c, n, i))
for d in range(7):
    wline = [gray_a(x0 + k, y - d) if (y - d) >= 0 else 0 for k in range(10)]
    print(" 行%d: %s" % (d, wline))

E = [[[0] * 4 for _ in range(GRP)] for _ in range(H)]
for yy in range(H):
    for nn in range(GRP):
        xx0 = 4 * nn - 3
        rows = []
        for dy in range(7):
            w = [gray_a(xx0 + k, yy - dy) if (yy - dy) >= 0 else 0 for k in range(10)]
            rows.append([sum(w[k:k + 5]) for k in range(6)])
        for ii in range(4):
            S1 = sum(rows[d][ii + 2] for d in range(5))
            S2 = sum(rows[d][ii] for d in range(5))
            S3 = sum(rows[d][ii + 1] for d in range(5))
            S4 = sum(rows[d][ii + 1] for d in range(2, 7))
            mag = abs(S1 - S2) + abs(S3 - S4)
            mean25 = S3 >> 4
            thr = section_floor(mean25) + ((mean25 * K) >> 5)
            strong = mag >= thr
            weak = mag >= (thr >> 1)
            up = E[yy - 1][nn] if yy - 1 >= 0 else [0, 0, 0, 0]
            up_prev = E[yy - 1][nn - 1] if (yy - 1 >= 0 and nn - 1 >= 0) else [0, 0, 0, 0]
            u0 = up_prev[3] if ii == 0 else up[ii - 1]
            left = E[yy][nn][ii - 1] if ii > 0 else (E[yy][nn - 1][3] if nn > 0 else 0)
            e = strong or (weak and (left or up[ii] or u0))
            if yy < 8: e = 0
            if nn == 0 and ii <= 2: e = 0
            if nn == GRP - 1 and ii >= 2: e = 0
            E[yy][nn][ii] = 1 if e else 0
            if (yy, nn, ii) == (y, n, i):
                print("目标像素: S1=%d S2=%d S3=%d S4=%d mag=%d mean25=%d thr=%d strong=%d weak=%d e=%d" % (S1, S2, S3, S4, mag, mean25, thr, strong, weak, E[yy][nn][ii]))