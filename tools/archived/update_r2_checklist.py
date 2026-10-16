# -*- coding: utf-8 -*-
"""一次性脚本：把 2026-10-16 算法被 TD 优化掉的排查结论固化进 R2 清单。
只做定点插入，不重写原文。"""
import io
import sys

sys.stdout.reconfigure(encoding='utf-8', errors='replace')

F = r'E:\fpga\contest_s2\docs\research\R2_开发过程保障清单.md'
s = io.open(F, encoding='utf-8').read()
n0 = len(s.split('\n'))

# ---------- A 段：追加 A10 ----------
key = '- **A9：'
i = s.find(key)
if i >= 0:
    eol = s.find('\n', i)
    a10 = (
        '\n- **A10：关键路径上的中间信号主动加 `(* keep = "true" *)`** —— TD 会把'
        '\u201c看似不影响输出\u201d的逻辑整片**常量传播**删掉。\n'
        '  **判据：综合后某模块 `ripple = 0` 就是被优化掉了**'
        '（2026-10-16 实测：算法 49 LUT / 0 ripple / 37 seq → 加 keep 后 '
        '**356 LUT / 39 ripple / 161 seq / 3 块 ERAM**）'
    )
    s = s[:eol] + a10 + s[eol:]
    print('OK  A10 已插入')
else:
    print('!!  未找到 A9 锚点')

# ---------- B 段：追加 B8 ----------
key = '| B7 |'
i = s.find(key)
if i >= 0:
    eol = s.find('\n', i)
    b8 = (
        '\n| B8 | **块 RAM 只用工程 `.al` 里已注册的 IP**（如 `blk_mem_gen_zhenghe`），'
        'HDL 里裸例化它的模块名即可 | \u26a0\ufe0f **裸例化 arch 库的 `PH1P_LOGIC_ERAM` 无效**'
        '（该原语是空壳，TD 只在 IP 流程里才映射成物理块 RAM）；'
        'reg 数组会被推断成 `LOGIC_RAMFIFO` 且深度推错（1024 vs 实际 1280） |'
    )
    s = s[:eol] + b8 + s[eol:]
    print('OK  B8 已插入')
else:
    print('!!  未找到 B7 锚点')

# ---------- E 段「写之后」：追加资源核对 ----------
key = '- [ ] TD 综合报告：ERAM 增量'
i = s.find(key)
if i >= 0:
    eol = s.find('\n', i)
    e_new = (
        '\n- [ ] **核对资源增量是否符合事前预估**（写代码时就在文件头写下预期值：LUT / FF / ERAM / DSP）\n'
        '      - **`ripple` 必须 > 0** —— 有进位链才说明加法器真的进了网表；'
        '`ripple = 0` 而代码里有加法/比较，就是被优化了\n'
        '      - 顶层 `#eram` / `#lut6` / `#reg` 的增量要与预估对得上'
        '（本次实测：`#eram` 5→8、`#luts` 1169→1522、`#registers` 1384→1519）'
    )
    s = s[:eol] + e_new + s[eol:]
    print('OK  E 段新增项已插入')
else:
    print('!!  未找到 E 段锚点')

# ---------- 文末：追加 F 段 ----------
f_sec = (
    '## F. 厂商工具行为必查项（安路 TD 专有 —— 2026-10-16 排查一整天换来）\n'
    '\n'
    '| #  | 坑                                                           | 表现                                                         | 对策                                                     |\n'
    '| -- | ------------------------------------------------------------ | ------------------------------------------------------------ | -------------------------------------------------------- |\n'
    '| F1 | **逻辑被常量传播整片删除**                                   | 某模块资源异常小、**`ripple = 0`**                          | 给关键中间信号加 `(* keep = "true" *)`                   |\n'
    '| F2 | **裸例化 arch 原语无效**                                     | `elaborate` 能找到模块、参数也对，但 `#eram` 不增加          | 只用 `.al` 的 `<IP_FILE>` 段注册过的 IP                  |\n'
    '| F3 | reg 数组被推成 `LOGIC_RAMFIFO` 且**深度推错**                | 日志出现 `PH1P_LOGIC_RAMFIFO(ADDR_WIDTH=10)`，而数组需 1280 深 | 同样改用已注册的 IP                                    |\n'
    '| F4 | **官方源码里的保留标记就是坑位地图**                         | 官方写 `(* keep = "true" *)`、`//synthesis keep`、`AutoExcluded` | **看到就追问\u201c官方为什么这么写\u201d**                |\n'
    '\n'
    '**排查铁律**：面对多种可能原因，**先做那个"一次实验就能切开一半假设空间"的**（如本次的 `keep`，'
    '一次编译即可区分"逻辑被删"还是"RAM 没落地"），而不是先做自己最熟悉的方向。\n'
    '\n'
    '**通用检索习惯**：开工前不要只查\u201c某某编码规范\u201d，要查\u201c**<工具名> <现象> 坑**\u201d；'
    '遇到异常先搜\u201c是不是工具已知行为\u201d，再怀疑自己的代码。\n'
)

key = '*本清单与'
i = s.find(key)
if i >= 0:
    s = s[:i] + f_sec + '\n---\n\n' + s[i:]
    print('OK  F 段已插入（文末说明之前）')
else:
    s = s + '\n' + f_sec
    print('OK  F 段已追加到文末')

io.open(F, 'w', encoding='utf-8').write(s)
print()
print('=== 行数：%d -> %d ===' % (n0, len(s.split('\n'))))
print('=== 新增的小节/条目 ===')
for ln in s.split('\n'):
    t = ln.strip()
    if t.startswith('## ') or t.startswith('- **A10') or t.startswith('| B8 ') or 'ripple` 必须' in t:
        print('   ' + t[:88])
