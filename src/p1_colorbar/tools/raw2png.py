# -*- coding: utf-8 -*-
"""
raw2png.py —— 把 tb_osd_overlay(+define+DUMP_FRAME) 导出的裸 RGB888 帧转成 PNG

用法:
    python raw2png.py osd_frame.raw out.png 1280 720
"""
import sys
import os
import zlib
import struct


def write_png(path, w, h, rows):
    raw = b"".join(b"\x00" + bytes(r) for r in rows)

    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    open(path, "wb").write(png)


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "osd_frame.raw"
    dst = sys.argv[2] if len(sys.argv) > 2 else "osd_frame.png"
    w = int(sys.argv[3]) if len(sys.argv) > 3 else 1280
    h = int(sys.argv[4]) if len(sys.argv) > 4 else 720
    data = open(src, "rb").read()
    need = w * h * 3
    if len(data) < need:
        raise SystemExit("裸流长度 %d < 需要 %d，仿真没有跑完一帧？" % (len(data), need))
    rows = [data[y * w * 3:(y + 1) * w * 3] for y in range(h)]
    write_png(dst, w, h, rows)
    print("wrote %s (%dx%d, %d bytes)" % (dst, w, h, os.path.getsize(dst)))


if __name__ == "__main__":
    main()
