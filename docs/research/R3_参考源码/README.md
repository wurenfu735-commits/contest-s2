# R3 调研参考源码

> 这两个文件是 R3 调研时**通读分析**的开源源码（保留以供答辩溯源"看过哪些、借鉴了什么"）。
> **明确声明：只借鉴思路、不复制代码**（2026-10-17 用户规则 + MEMORY 八节第 4 条）。
> 我们落地实现（`rtl\edge_adaptive_96.v`）没有抄用其中任何一段，借鉴的是架构模式，
> 详见 `..\R3_并行窗口与行缓存架构调研.md` 第四节的决议。

| 文件 | 来源仓库 | 借鉴了什么（思路层面） |
|---|---|---|
| `conv2d.sv` | dannyboy1024/FPGA-streaming-line-buffer-based-2D-convolution-kernel | 部分和存 RAM、行内滑窗的"增量"思想（我们**未采用**其实现，仅评估） |
| `sobel_convolution.v` | AngeloJacobo/FPGA_RealTime_and_Static_Sobel_Edge_Detection | separable 分离卷积（先横向一维和/差，再纵向组合）——与我们的 col5 列和 → 纵向组合同一思路 |

## 采用情况（对照 v4 最终设计）

- **采用**：separable 第一步（行内 5 列滑动和 → 纵向 5 行组合），这是公开的算子恒等式思路。
- **未采用**：running sum 增量滑窗（资源不紧张，不引入更长的组合链）、部分和存 RAM（我们 4 像素并行取窗口，不适用串行滑窗模式）。
- **全部代码**：`edge_adaptive_96.v` 的窗口/延迟链/迟滞/四态均为结合自研接口（96bit、4 像素/拍）独立编写。