#!/usr/bin/env python3
# gen_golden_cartoon.py —— 卡通化黄金模型（颜色量化 + 边缘压黑）
# 对应赛题扩展①「风格化/视觉增强」
#
# 算法（与 RTL 同构）：
#   1) 量化：每通道取高 QBITS 位（默认 3），低位清零
#      R_q = (R >> (8-QBITS)) << (8-QBITS)   例：QBITS=3 → R & 0xE0
#   2) 边缘压黑：边缘像素（二值图非 0）输出 0
#
# RTL 必须逐像素对齐本模型。
QBITS = 3

def quantize(v):
    """单通道量化：取高 QBITS 位，低位清零"""
    return (v >> (8 - QBITS)) << (8 - QBITS)

def cartoon_pixel(r, g, b, edge):
    """单像素卡通化。edge=True 表示是边缘（压黑）"""
    if edge:
        return (0, 0, 0)
    return (quantize(r), quantize(g), quantize(b))

if __name__ == "__main__":
    # 自检用例（RTL tb 用同一组）
    cases = [
        # (r, g, b, edge, 期望量化结果)
        (0xB2, 0x35, 0x7A, False, (0xA0, 0x20, 0x60)),  # 0xB2=1011_0010 → 1010_0000=0xA0
        (0x00, 0x00, 0x00, False, (0x00, 0x00, 0x00)),
        (0xFF, 0xFF, 0xFF, False, (0xE0, 0xE0, 0xE0)),  # 0xFF → 1110_0000=0xE0
        (0x1F, 0x2F, 0x3F, False, (0x00, 0x20, 0x20)),  # 0x1F=0001_1111 → 0x00
        (0xB2, 0x35, 0x7A, True,  (0x00, 0x00, 0x00)),  # 边缘 → 全黑
    ]
    ok = True
    for r, g, b, edge, exp in cases:
        got = cartoon_pixel(r, g, b, edge)
        flag = "OK " if got == exp else "BAD"
        if got != exp:
            ok = False
        print(f"{flag} in=({r:#04x},{g:#04x},{b:#04x}) edge={edge} -> got={tuple(hex(x) for x in got)} exp={tuple(hex(x) for x in exp)}")
    print("==== golden_cartoon", "PASS" if ok else "FAIL", "====")
