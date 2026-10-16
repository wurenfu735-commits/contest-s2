# -*- coding: utf-8 -*-
"""v4 数据依据：噪声幅度 vs 局部亮度 统计
素材：assets/video_frames/a3_check2（A3 原图态 I_mode=0 的上板视频抽帧）
方法：每帧 32×32 分块 → 块内均值/标准差 → 按亮度分 bin 取下包络（近似"平坦块噪声"）。
局限（重要，写进结论）：素材是"手机拍显示器"的二次拍摄，含拍摄噪声/摩尔纹/视角变化，
不是传感器直出数据；结果只作分段点量级参考，精确校准将来用 UART/ChipWatcher 直出。
"""
import os, glob
import numpy as np
from PIL import Image

d = r"E:\fpga\contest_s2\assets\video_frames\a3_check2"
frames = sorted(glob.glob(os.path.join(d, "f_*.png")))
print("帧数:", len(frames))

blocks = []
for fp in frames:
    im = np.asarray(Image.open(fp).convert("L")).astype(np.float32)
    H, W = im.shape
    BS = 32
    for y in range(0, H - BS, BS):
        for x in range(0, W - BS, BS):
            blk = im[y:y+BS, x:x+BS]
            blocks.append((blk.mean(), blk.std()))
mean_arr = np.array([b[0] for b in blocks])
std_arr  = np.array([b[1] for b in blocks])
print("总块数:", len(blocks))

bins = list(range(0, 256, 16))
print("\n亮度区间 | 块数 | 噪声σ(下包络p10) | σ(中位) | 备注")
for lo in bins:
    hi = lo + 15
    m = (mean_arr >= lo) & (mean_arr <= hi)
    n = int(m.sum())
    if n < 5:
        continue
    p10 = np.percentile(std_arr[m], 10)
    p50 = np.percentile(std_arr[m], 50)
    tag = ""
    if lo < 48: tag = "<- 暗区(噪声大)"
    elif lo > 160: tag = "<- 亮区"
    print("  %3d-%3d | %5d | %6.1f          | %6.1f   | %s" % (lo, hi, n, p10, p50, tag))