# -*- coding: utf-8 -*-
"""把 B4 的 OSD 两个 RTL 文件登记进 OUR_p1_colorbar.al（幂等，可重复执行）。

用途：xunlei 里的 zip 只是快照，你们真实工程在别处（.al 里记的 E:/fpga/contest_s2/...）。
      如果那边还没登记 OSD 文件，改这一行的路径后跑一次即可。

做法：
  1. 在 <Verilog> 段末尾（</Verilog> 之前）追加
       ../../../rtl/osd_overlay.v     （CompileOrder = 现有最大值 + 1）
       ../../../rtl/osd_logo_rom.v    （CompileOrder = 现有最大值 + 2）
  2. 已经在列就跳过，不会重复插入
  3. 原文件先备份成 *.bak_before_osd

用法：
    python patch_al_osd.py [OUR_p1_colorbar.al 的路径]
"""
import io
import os
import re
import shutil
import sys

DEFAULT_AL = r"E:\xunlei\contest-s2-main\src\p1_colorbar\OUR_project\hdmi_base_src\td_project\OUR_p1_colorbar.al"

FILES = [
    ("../../../rtl/osd_overlay.v",  "osd_overlay.v  "),
    ("../../../rtl/osd_logo_rom.v", "osd_logo_rom.v "),
]


def entry(path, order):
    return ('            <File Path="%s">\n'
            '                <FileInfo>\n'
            '                    <Attr Name="UsedInSyn" Val="true"/>\n'
            '                    <Attr Name="UsedInP&R" Val="true"/>\n'
            '                    <Attr Name="BelongTo" Val="design_1"/>\n'
            '                    <Attr Name="CompileOrder" Val="%d"/>\n'
            '                </FileInfo>\n'
            '            </File>\n') % (path, order)


def main():
    al = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_AL
    if not os.path.isfile(al):
        raise SystemExit("找不到 .al: %s" % al)

    with io.open(al, "r", encoding="utf-8") as f:
        src = f.read()

    if "</Verilog>" not in src:
        raise SystemExit("!! 这个 .al 里没有 </Verilog> 段，格式不对")

    orders = [int(m) for m in re.findall(r'Name="CompileOrder" Val="(\d+)"', src)]
    order = max(orders) + 1 if orders else 1

    add = []
    for path, label in FILES:
        if path in src:
            print("  %s 已在列，跳过" % label)
        else:
            add.append(entry(path, order))
            print("  %s 已登记（CompileOrder=%d）" % (label, order))
            order += 1

    if not add:
        print("无需修改：OSD 文件都已在工程里。")
        return

    backup = al + ".bak_before_osd"
    if not os.path.exists(backup):
        shutil.copy2(al, backup)
        print("  备份 -> %s" % backup)

    src = src.replace("        </Verilog>\n", "".join(add) + "        </Verilog>\n", 1)
    with io.open(al, "w", encoding="utf-8", newline="\n") as f:
        f.write(src)
    print("完成：%s" % al)


if __name__ == "__main__":
    main()
