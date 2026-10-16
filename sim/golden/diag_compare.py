"""RTL vs 期望 差异精细诊断（定位误差模式）"""
import sys
from collections import Counter

OUT = r"E:\fpga\contest_s2\sim\golden\out"


def load(path):
    vals = []
    with open(path, "r", encoding="ascii", errors="replace") as f:
        for line in f:
            s = line.strip()
            if s:
                vals.append(int(s, 16) if any(c in "abcdefABCDEF" for c in s) else int(s))
    return vals


rtl = [1 if v else 0 for v in load(OUT + r"\rtl_edge_out.txt")]
exp = [1 if v else 0 for v in load(OUT + r"\edge_colorbar.txt")]
W = 640
print(f"len(rtl)={len(rtl)}  len(exp)={len(exp)}  diff={len(rtl)-len(exp)}")

print("\n=== 前 20 个输出对比（off=-1 对齐后）===")
print(" i | rtl | exp[i-1] | 备注")
for i in range(0, 12):
    e = exp[i - 1] if 0 <= i - 1 < len(exp) else None
    flag = "" if e is None or rtl[i] == e else "  <-- DIFF"
    print(f"{i:3d} |  {rtl[i]}  |   {e}    |{flag}")

# 用 off=-1 统计每行误差位置
off = -1
row_err = Counter()
col_err = Counter()
for i in range(max(0, -off), min(len(rtl), len(exp) - off)):
    if rtl[i] != exp[i + off]:
        idx = i + off
        row_err[idx // W] += 1
        col_err[idx % W] += 1

print(f"\n=== 误差行分布（共 {sum(row_err.values())} 个）===")
print("误差最多的 10 行:", row_err.most_common(10))
print("误差最少的行数:", len([r for r in range(360) if row_err.get(r, 0) == 0]))

print("\n=== 误差列分布（前 20 个高频列）===")
print(col_err.most_common(20))

# 针对"每行 10 个误差"的行（第 3 行）看具体列
for probe_row in (3, 100, 359):
    cols = [c for c in range(W) if (probe_row * W + c) < len(exp)
            and (probe_row * W + c + off) < len(rtl)
            and rtl[probe_row * W + c + off] != exp[probe_row * W + c]]
    print(f"\n第 {probe_row} 行误差列（{len(cols)} 个）: {cols[:30]}")
    if cols:
        c = cols[0]
        print(f"   首错列 {c}: rtl={rtl[probe_row*W+c+off]} exp={exp[probe_row*W+c]}")
        # 打印该列附近 6 列的期望与 RTL
        lo = max(0, c - 3)
        hi = min(W, c + 4)
        print("   期望:", [exp[probe_row * W + x] for x in range(lo, hi)])
        print("   RTL :", [rtl[probe_row * W + x + off] for x in range(lo, hi)])
