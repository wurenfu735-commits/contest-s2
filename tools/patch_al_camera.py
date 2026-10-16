# -*- coding: utf-8 -*-
"""把 OUR_p1_colorbar.al 从 TPG 版切回摄像头版：
1. 加 design_top_wrapper.v（顶层，Verilog 段第一条）
2. 加 edge_adaptive_96.v（自研算法）
3. TOP_MODULE 改 design_top_wrapper
4. 约束 .adc 换成官方 pin.adc
"""
import io, sys

AL = r"E:\fpga\contest_s2\src\p1_colorbar\OUR_project\hdmi_base_src\td_project\OUR_p1_colorbar.al"

with io.open(AL, "r", encoding="utf-8") as f:
    src = f.read()

changed = []

# ---- 1) 顶层 design_top_wrapper.v 插入到 <Verilog> 段第一条 ----
top_entry = '''            <File Path="../user_source/hdl_source/design_top_wrapper.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="1"/>
                </FileInfo>
            </File>
'''
anchor = "        <Verilog>\n"
if "design_top_wrapper.v" not in src:
    if anchor in src:
        src = src.replace(anchor, anchor + top_entry, 1)
        changed.append("design_top_wrapper.v 已加入")
    else:
        print("!! 找不到 <Verilog> 段锚点"); sys.exit(1)
else:
    print("design_top_wrapper.v 已在列，跳过")

# ---- 2) edge_adaptive_96.v 插入到 edge_adaptive_pixel.v 之后 ----
edge96 = '''            <File Path="../../../rtl/edge_adaptive_96.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="59"/>
                </FileInfo>
            </File>
'''
if "edge_adaptive_96.v" not in src:
    # 找到 edge_adaptive_pixel.v 的 </File> 结束位置，插到它后面
    marker = '../../../rtl/edge_adaptive_pixel.v"'
    idx = src.find(marker)
    if idx < 0:
        print("!! 找不到 edge_adaptive_pixel.v"); sys.exit(1)
    close = src.find("</File>", idx)
    if close < 0:
        print("!! 找不到 edge_adaptive_pixel 的 </File>"); sys.exit(1)
    ins = close + len("</File>") + 1   # 跳过 </File> 和换行
    src = src[:ins] + edge96 + src[ins:]
    changed.append("edge_adaptive_96.v 已加入")
else:
    print("edge_adaptive_96.v 已在列，跳过")

# ---- 3) TOP_MODULE 改 design_top_wrapper ----
src = src.replace("<LABEL>colorbar_top</LABEL>", "<LABEL>design_top_wrapper</LABEL>")
src = src.replace("<MODULE>colorbar_top</MODULE>", "<MODULE>design_top_wrapper</MODULE>")
changed.append("TOP_MODULE -> design_top_wrapper")

# ---- 4) 约束 .adc 换成官方 pin.adc ----
src = src.replace(
    '<File Path="../../../constraints/colorbar_top.adc">',
    '<File Path="../user_source/constraints_source/pin.adc">',
)
changed.append(".adc -> pin.adc")

# ---- 5) 移除 TPG 版顶层 colorbar_top.v 条目（方案 A：文件留盘，仅移除 .al 列表）----
cbt = '            <File Path="../../../rtl/colorbar_top.v">\n'
if cbt in src:
    i = src.find(cbt)
    j = src.find("</File>", i)
    src = src[:i] + src[j + len("</File>") + 1:]
    changed.append("colorbar_top.v 已移除")
else:
    print("colorbar_top.v 不在列，跳过")

with io.open(AL, "w", encoding="utf-8") as f:
    f.write(src)

print("=== 完成 ===")
for c in changed:
    print("  " + c)