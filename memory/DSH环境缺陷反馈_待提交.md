# DSH 环境缺陷反馈报告（待提交官方）

## 摘要
DSH 桌面端中 `pwsh` 工具无法执行任何命令：每次运行都返回 `exit code 3221225794`（= Windows STATUS_DLL_INIT_FAILED / 0xC0000142），无任何输出。已做系统性排除，判定为 DSH 客户端组件与当前系统环境的兼容性缺陷。

## 环境信息
- DSH 桌面端版本：`0.2.0-rc.2`（runtime.json：`D:\dsh-home\dsh-runtimes\dsh-primary-runtime\runtime.json`；客户端"检查更新"显示已是最新）
- 操作系统：Windows 11 24H2，build 26100（10.0.26100.0，2026-10 更新）
- 架构：x64；用户数据目录：`D:\dsh-home`（曾从 C 盘迁移，存在 `.migrated-from-C\` 痕迹）
- 已安装 PowerShell：Windows PowerShell 5.1（powershell.exe，正常）；PowerShell 7.6.6 MSI（C:\Program Files\PowerShell\7\pwsh.exe，正常）
- 安全软件：无第三方杀软（仅系统自带）
- DSH 运行时中的执行组件（观察到）：`node-pty`（含 `conpty.dll`、`OpenConsole.exe`，third_party\conpty\1.25.260303002 覆盖 win10-x64/arm64）

## 现象（稳定复现）
- DSH 会话中调用 pwsh 工具（任意命令，如 `Write-Output "hi"`）：前台 / `run_in_background` / 更换工作目录（C:\、E:\fpga）均报 `[exit code: 3221225794]`，无 stdout/stderr。
- 同一台机器、同一用户，**手动运行** `powershell.exe` 与 `pwsh.exe` 全部正常。
- DSH 内其它不依赖子进程的工具（文件读写/搜索）工作正常。

## 已排除项（附证据）
1. ❌ 系统缺 PowerShell 7：曾先后安装 Store 版、MSI 版 pwsh 7.6.6，`pwsh --version` 正常；DSH 内依旧 0xC0000142。
2. ❌ 第三方杀软拦截：机器无 360/火绒等，仅系统 Defender。
3. ❌ DSH 运行时状态损坏：完全退出桌面端（含托盘）重启后依旧。
4. ❌ 命令内容 / 工作目录 / 前后台模式因素：均逐一对比复现。
5. ❌ 版本过旧可升级修复：客户端自检为最新版本后问题仍在。

## 推测方向（供官方定位）
- node-pty/ConPTY 拉起 shell 的组件（`conpty.dll`＋`OpenConsole.exe`）在本系统上的初始化失败，导致子进程启动即 DLL_INIT_FAILED；
- 或 DSH 的文件沙箱注入机制在 Win11 24H2（build 26100）上未正确工作；
- C→D 迁移后可能存在失效的绝对路径/组件引用。

## 反馈建议
请官方提供：①诊断日志开启方式（或日志路径）以便提取 spawn 失败明细；②是否有可关闭"进程沙箱/伪终端"的兼容选项；③针对 Win11 24H2 的已知修复版本。

## 工作影响
由于该缺陷，AI 无法自主执行命令（编译/仿真/复制文件均不可），当前工作模式为：AI 编写脚本与步骤文档 → 用户手动在 TD/ModelSim 执行 → AI 读日志排错。功能可推进但效率受限。