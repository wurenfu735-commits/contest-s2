from pathlib import Path
# -*- coding: utf-8 -*-
"""
为队友的 OUR_p1_colorbar.al 生成 TD 无头构建所需的 run 目录。

背景：仓库 .gitignore 排除了 `*_Runs/`，所以这台机器上从来没有生成过 run 目录，
      而 build/rebuild 脚本都依赖 <run>/settings.cfg + <run>/<name>.prj。
      本脚本从 .al 直接生成这两样东西，之后就能用 td_build.ps1 无头构建。

★ 路径换算：.al 位于 td_project/，而 .prj 位于 td_project/<name>_Runs/syn_1/
  二者相差 2 层，所以给 .al 里每一个 <File Path="..."> 前面统一加 "../../"。
  验证：../user_source/x  -> ../../../user_source/x  (3 层上溯 = hdmi_base_src/) ✅
        ../../../rtl/x     -> ../../../../../rtl/x     (5 层上溯 = p1_colorbar/) ✅
        al_ip/x            -> ../../al_ip/x            (2 层上溯 = td_project/)  ✅
"""
import os, re, sys, shutil

REPO = str(Path(__file__).resolve().parents[1])
PROJ = os.path.join(REPO,"OUR_project/hdmi_base_src/td_project")
NAME = "OUR_K1_4mode"
AL   = os.path.join(PROJ, NAME + ".al")
SDC  = NAME + ".sdc"
RUNS = os.path.join(PROJ, NAME + "_Runs")


def main():
    if not os.path.exists(AL):
        sys.exit("找不到 .al: " + AL)
    al = open(AL, encoding="utf-8-sig").read()

    # ---- 1) 生成 .prj：所有路径前加 ../../ ----
    def prepend(m):
        p = m.group(1)
        return '<File Path="../../%s"' % p
    prj = re.sub(r'<File Path="([^"]+)"', prepend, al)

    n_files = len(re.findall(r'<File Path=', prj))
    print("源文件条目: %d" % n_files)

    for stage in ("syn_1", "phy_1"):
        rd = os.path.join(RUNS, stage)
        os.makedirs(rd, exist_ok=True)
        with open(os.path.join(rd, NAME + ".prj"), "w", encoding="utf-8", newline="") as f:
            f.write(prj)
        print("  写入 %s\\%s.prj" % (stage, NAME))

    # ---- 2) 生成 settings.cfg ----
    # 参照 lab_ex3 的官方格式；SDC 在 .al 里没有 SDC_FILE 段，手动补进 SDCList
    common = """# This File is Created by Tang Dynasty.
# 由 generate_runs.py 生成（仓库里 *_Runs/ 被 gitignore，需重建）

set ADCList {{"../../../user_source/constraints_source/pin.adc"}}

set IpADCList {{ ddr2 ../../../user_source/hdl_source/ph1p35_ddr/ddr2/src/adc/ddr2.adc }}

set IpSDCList {{ ddr2 ../../../user_source/hdl_source/ph1p35_ddr/ddr2/src/sdc/ddr2.sdc w128_d512_fifo ../../../user_source/ip_source/w128_d512_fifo/w128_d512_fifo.tcl }}

set SDCList {{"../../{sdc}"}}

set area_option -packarea

set device_name ph1_35p.db

set package_name PH1P35MDG324

set prj_name {{{name}}}

set speed 3

set top_model_name {{design_top_wrapper}}
"""

    syn = common.format(sdc=SDC, name=NAME) + """
set end_step opt_gate

set run_type syn

set start_step read_design
"""
    phy = common.format(sdc=SDC, name=NAME) + """
set arr_filter false

set drHoldFix on

set end_step bitgen

set parent ../syn_1

set run_type phy

set start_step opt_place
"""

    for stage, body in (("syn_1", syn), ("phy_1", phy)):
        p = os.path.join(RUNS, stage, "settings.cfg")
        with open(p, "w", encoding="utf-8", newline="\r\n") as f:
            f.write(body)
        print("  写入 %s\\settings.cfg" % stage)

    # ---- 3) 自检：抽查几个路径是否真实存在 ----
    print()
    print("路径自检（从 %s\\syn_1\\ 解析）:" % os.path.basename(RUNS))
    samples = [
        "../../../user_source/hdl_source/design_top_wrapper.v",
        "../../../user_source/constraints_source/pin.adc",
        "../../../../../rtl/image_modes4.v",
        "../../../user_source/hdl_source/ph1p35_ddr/ddr2/ddr2.xml",
        "../../al_ip/ChipWatcher_mipi/ChipWatcher_mipi.xml",
        "../../" + SDC,
    ]
    base = os.path.join(RUNS, "syn_1")
    for s in samples:
        full = os.path.normpath(os.path.join(base, s))
        ok = os.path.exists(full)
        print("  %s  %s" % ("OK  " if ok else "MISS", s))
        if not ok:
            print("        -> " + full)

    # 用真实文件表再全量检查一遍
    bad = 0
    for m in re.finditer(r'<File Path="../../([^"]+)"', prj):
        rel = m.group(1)
        full = os.path.normpath(os.path.join(base, "../../" + rel))
        if not os.path.exists(full):
            bad += 1
            if bad <= 10:
                print("  MISS %s" % rel)
    print("全量检查：%d 个路径不存在" % bad)
    if bad:
        sys.exit(1)


if __name__ == "__main__":
    main()
