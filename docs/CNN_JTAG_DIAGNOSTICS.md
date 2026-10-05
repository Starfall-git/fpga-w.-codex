# Ti60 DMI 超时定位（2026-10-05）

阶段 6 的调试子步骤；CPU 访问与 INT8 板上自检尚未通过。

## 已有证据

用户确认 v0.5-ti60-debug-r1 的 JTAG `.bit` 已下载，HDMI 为随场景变化的实时摄像头画面、COM8 能连接。最新 OpenOCD 能读到 Ti60 ID `0x10660a79`，随后重复报告 DMI operation didn't complete in 2 seconds。不能继续把当前故障归因于未下载 ELF，也不能把此前的 `dtmcontrol=0xffffffff` 当作当前日志的全部表现。GDB 依赖 OpenOCD 成功访问 CPU。

本地核对：顶层 USER1 的 TCK/TDI/TDO/SEL/CAPTURE/SHIFT/UPDATE/RESET 与官方 YOLO demo 对应；生成 BSP 配置使用 IR length 5、`riscv use_bscan_tunnel 6 1`、IR 8。实际 Sapphire 使用 DebugTransportModuleTunneled。CPU/内存/外设接 DDR 用户时钟；`cnn_ai_reset` 在 DDR 校准通过、事务端口 quiescent 后释放外部复位，再等待 SoC 的三个复位输出释放。调试域自身复位也受外部 ai_reset 影响。上述源码检查不能替代板上信号观测。

LED0=sys_pll_lock，LED1=cam_pll_lock，LED2=DDR cal_done，LED3=DDR cal_pass（默认 DEBUG_LEDS=1）。这是信号映射，灯的亮灭还要按板卡有效电平解释。请同时记录 HDMI 是否为随场景变化的实时摄像头画面。

`GET_CNN.available` 还依赖软件 firmware_ready；静态固件不设置它，所以 GUI“未就绪”不能单独证明 SoC 一直处于复位。

## 下一次实验：100 kHz 与详细日志

在独立 FPGA 副本根目录执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\diagnose_evsoc_jtag.ps1
```

默认读用户解压的 `deliverables/v0.5-ti60-debug-r1`。如解压在别处，传 `-ReleaseDir '实际路径'`。脚本只在 artifacts/jtag-diagnostics 下生成有效配置及日志，保留 release 和 BSP 原文件。可用 `-PrepareOnly` 检查文件及生成配置，不访问板卡。

先退出旧 OpenOCD、IDE Debug 会话及 Programmer 活动连接；保持已下载的业务 `.bit`，不要断电。脚本启动厂商 RISCV-IDE 的 OpenOCD，保留官方 init/halt，可能暂停 CPU；不加载 ELF、不写 Flash。日志写在终端打印的目录内 `openocd.log`。首次默认100 kHz，重复超时约30秒后 Ctrl+C，保留整个日志及 metadata.json。若要用相同日志级别比较原速率，结束前一会话后加 `-SpeedKHz 800`；一次只运行一个实例。

若成功 examine 并 halt CPU，保持 OpenOCD 运行，再从 release 目录运行 start-gdb.ps1。仅显示端口3333监听不算成功。若仍 DMI 超时，先分析日志中 DTMCS、DMI busy、dmstatus 和复位行为，再决定仪器观测或新硬件诊断版本。

降低速率只是排查链路敏感性。当前跨域 setup -1.307/-0.384 ns 尚未签核，低速通过也不能证明跨域约束正确。没有把这些路径统一设为 false path，也没有修改硬件来绕过复位。

OpenOCD 的 `riscv set_command_timeout_sec` 仅改变命令等待时限，不修复时钟/复位/传输链路，参见[官方命令说明](https://openocd.org/doc-release/html/Architecture-and-Core-Commands.html)。此次保持原超时设置，避免同时改变多个变量。

## 验证边界

脚本需通过 PowerShell 语法解析、PrepareOnly 与有效配置差异检查。本次没有代用户访问 JTAG、下载镜像或加载 ELF；100 kHz 板上结果待用户反馈。v0.5-ti60-debug-r1 原 ZIP 与 manifest 保持发布时快照，最新板上反馈以本文为准。
