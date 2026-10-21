"""RTL 输出与黄金模型期望的逐像素比对（自动对齐 + 误差定位）

用法：
    python align_compare.py rtl_edge_out.txt edge_colorbar.txt [IMG_W]

输出：
    - 两侧序列长度、最佳对齐偏移
    - 误差像素数 / 比对像素数
    - 第一个误差的行列位置与两边取值
    - 误差分布诊断（行首 / 行尾 / 集中行 / 均匀散布）
"""
import sys


def load_ints(path: str):
    """读 0/1 序列；十六进制字母按 hex 解析；x/X（不定态）计为 0 并单独统计。

    注意：不能因为 X 而丢弃该元素——否则序列长度变化会导致整体对齐错位、产生大量虚警误差。
    """
    vals, n_x = [], 0
    with open(path, "r", encoding="ascii", errors="replace") as f:
        for line in f:
            s = line.strip()
            if not s:
                continue
            if s.lower() in ("x", "z"):
                vals.append(0)
                n_x += 1
                continue
            try:
                vals.append(int(s, 16) if any(ch in "abcdefABCDEF" for ch in s) else int(s))
            except ValueError:
                vals.append(0)
                n_x += 1
    if n_x:
        print(f"  [注意] {path} 中有 {n_x} 个不定态(x/z)，已按 0 参与比对")
    return vals


def main() -> None:
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)

    rtl_path, exp_path = sys.argv[1], sys.argv[2]
    img_w = int(sys.argv[3]) if len(sys.argv) > 3 else 640

    rtl = load_ints(rtl_path)
    exp = [1 if v else 0 for v in load_ints(exp_path)]
    rtl = [1 if v else 0 for v in rtl]

    print(f"RTL 输出序列 : {len(rtl)} 个")
    print(f"期望序列     : {len(exp)} 个")

    # ---- 自动对齐：找使误差最小的偏移 ----
    best = None
    for off in range(-30, 31):
        lo = max(0, -off)
        hi = min(len(rtl), len(exp) - off)
        if hi - lo < 100:
            continue
        err = 0
        for i in range(lo, hi):
            if rtl[i] != exp[i + off]:
                err += 1
        if best is None or err < best[0]:
            best = (err, off, lo, hi)

    if best is None:
        print("!! 无法对齐（序列太短）")
        sys.exit(1)

    err, off, lo, hi, = best
    n = hi - lo
    print(f"最佳对齐偏移 : {off}  （RTL 第 i 个 <-> 期望第 i+{off} 个）")
    print(f"比对像素数   : {n}")
    print(f"误差像素数   : {err}   ({100.0*err/max(1,n):.4f}%)")

    if err == 0:
        print("VERDICT: ALL PASSED (逐像素 0 误差)")
        return

    # ---- 第一个误差的位置与取值 ----
    first = None
    for i in range(lo, hi):
        if rtl[i] != exp[i + off]:
            first = i
            break
    if first is not None:
        idx = first + off
        row, col = divmod(idx, img_w)
        print(f"第一个误差   : RTL[{first}]={rtl[first]} vs 期望[{idx}]={exp[idx]}"
              f"  -> 第 {row} 行 第 {col} 列")

    # ---- 误差分布诊断 ----
    rows = {}
    col_bins = {"行首(0-3)": 0, "行尾(-4:)": 0, "中部": 0}
    for i in range(lo, hi):
        if rtl[i] == exp[i + off]:
            continue
        idx = i + off
        r, c = divmod(idx, img_w)
        rows[r] = rows.get(r, 0) + 1
        if c <= 3:
            col_bins["行首(0-3)"] += 1
        elif c >= img_w - 4:
            col_bins["行尾(-4:)"] += 1
        else:
            col_bins["中部"] += 1

    top_rows = sorted(rows.items(), key=lambda kv: -kv[1])[:8]
    print("误差最多的行 : " + ", ".join(f"第{r}行({n2})" for r, n2 in top_rows))
    print("列分布       : " + ", ".join(f"{k}={v}" for k, v in col_bins.items()))
    print("VERDICT: HAS ERRORS")

    # 诊断提示
    if col_bins["行首(0-3)"] > err * 0.5:
        print("  >> 提示：误差集中在行首，检查行缓存写指针/行首复位")
    if len(rows) <= 4 and err > 50:
        print("  >> 提示：误差集中在少数行，检查行缓存行切换（上上行对齐）")
    if col_bins["中部"] > err * 0.8:
        print("  >> 提示：误差均匀散布，检查阈值/位宽/迟滞邻居")


if __name__ == "__main__":
    main()
