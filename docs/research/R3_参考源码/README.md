# R3 调研参考源码

> **本目录不再存放第三方源码原文**（2026-10-18 移除）。
>
> 原因：原先存放的两个文件出自 GitHub 公开仓库，但**两个仓库都没有 License 声明**
> （无 License = 默认保留所有权利）。把它们的源码原文放进参赛提交仓库属于**再分发**，
> 与"只借鉴思路、不复制代码"的自我要求也不一致。为消除这一处风险，已删除原文，
> **只保留来源链接与分析结论**，溯源照样能做——答辩时讲"看了哪个仓库的哪个思路"即可。
>
> 需要复看原文时，按下面链接自行获取（不进入本仓库）。

## 一、看过什么、借鉴了什么

| 原文件名 | 来源仓库 | 借鉴了什么（思路层面） | 许可 |
|---|---|---|---|
| `conv2d.sv` | [dannyboy1024/FPGA-streaming-line-buffer-based-2D-convolution-kernel](https://github.com/dannyboy1024/FPGA-streaming-line-buffer-based-2D-convolution-kernel) | 部分和存 RAM、行内滑窗的"增量"思想（我们**未采用**其实现，仅评估） | 无 License |
| `sobel_convolution.v` | [AngeloJacobo/FPGA_RealTime_and_Static_Sobel_Edge_Detection](https://github.com/AngeloJacobo/FPGA_RealTime_and_Static_Sobel_Edge_Detection) | separable 分离卷积（先横向一维和/差，再纵向组合）——与我们的 col5 列和 → 纵向组合同一思路 | 无 License |

## 二、采用情况（对照 v5 最终设计）

- **采用**：separable 第一步（行内 5 列滑动和 → 纵向 5 行组合），这是公开的算子恒等式思路。
- **未采用**：running sum 增量滑窗（资源不紧张，不引入更长的组合链）、部分和存 RAM（我们 4 像素并行取窗口，不适用串行滑窗模式）。
- **全部代码自研**：`rtl/edge_adaptive_96.v` 的窗口/延迟链/迟滞/四态均为结合自研接口（96bit、4 像素/拍）独立编写，未逐行参考上述实现。

详见 `../R3_并行窗口与行缓存架构调研.md` 第四节的决议。

## 三、这条纪律的出处

`../R1_自适应阈值边缘检测.md` 第四节盘点了 5 个开源工程的许可状态：**除 `medalotte/HLS-canny-edge-detection` 是 MIT 外，其余均无 License 或为 GPL-3.0（传染性）**。
所以对这批工程一律**只看思路、不拿代码**；同理，本仓库也不再保存它们的源码原文。
