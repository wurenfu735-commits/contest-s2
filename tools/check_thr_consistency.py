"""核对：RTL 的阈值参数默认值 与 黄金模型的 section_floor 是否严格一致

为什么需要：阈值分段在两处各写一份——RTL 的 `THR_FLOOR + THR_ADD_D0..D3`
和黄金模型的 `section_floor()`。改一边忘另一边，tb 比对就会莫名其妙失配，
而且失配点在 400+ 像素里只出现在暗区，很难一眼看出来。

用法：python tools/check_thr_consistency.py
退出码：0 = 一致；1 = 不一致（可直接挂进 CI / 提交前检查）
"""
import io
import os
import re
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
rtl_path = os.path.join(ROOT, "src", "p1_colorbar", "rtl", "edge_adaptive_96.v")
py_path = os.path.join(ROOT, "tools", "gen_golden_v4.py")

rtl = open(rtl_path, encoding="utf-8", errors="replace").read()
py = open(py_path, encoding="utf-8", errors="replace").read()


def param(name):
    m = re.search(r"parameter\s*\[[^\]]*\]\s*" + name + r"\s*=\s*\d+'d(\d+)", rtl)
    if not m:
        raise SystemExit(f"!! RTL 里找不到参数 {name}")
    return int(m.group(1))


floor = param("THR_FLOOR")
adds = [param(f"THR_ADD_D{i}") for i in range(4)]
rtl_curve = [floor + a for a in adds]

print("RTL  参数：THR_FLOOR=%d, THR_ADD_D0..D3=%s" % (floor, adds))
print("RTL  四档地板 = %s" % rtl_curve)

m = re.search(r"def section_floor\(mean25\):(.*?)\n\n", py, re.S)
if not m:
    raise SystemExit("!! 黄金模型里找不到 section_floor")
py_curve = [int(x) for x in re.findall(r"return\s+(\d+)", m.group(1))]
print("黄金模型四档  = %s" % py_curve)

ok = rtl_curve == py_curve
print()
print("一致性：" + ("✅ 完全一致" if ok else "❌ 不一致！"))

# 顺带抓一遍注释里写死的默认值，防止文档漂移
stale = []
for mm in re.finditer(r"v5 默认 \{([\d,\s]+)\}\s*→", rtl):
    got = [int(v) for v in mm.group(1).replace(" ", "").split(",")]
    if got != adds:
        line = rtl[: mm.start()].count("\n") + 1
        stale.append("第 %d 行注释写 {%s}，实际参数是 %s" % (line, mm.group(1), adds))
if stale:
    print("⚠️ 注释与参数不一致：")
    for s in stale:
        print("  " + s)
else:
    print("注释：一致")

print()
print("各档最小可检对比度 Δmin = thr/10（竖直阶跃 mag=10Δ）：")
for name, thr in zip(["暗区(<41)", "次暗(41-82)", "中(82-123)", "亮区(>=123)"], rtl_curve):
    print("  %-13s thr=%3d  →  Δmin ≈ %.1f 灰度级" % (name, thr, thr / 10.0))

if not ok:
    print()
    print("  RTL  =%s" % rtl_curve)
    print("  模型 =%s" % py_curve)
    sys.exit(1)
