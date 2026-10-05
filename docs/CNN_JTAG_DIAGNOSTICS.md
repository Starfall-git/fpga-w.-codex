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

## 100 kHz 用户反馈与日志修复（2026-10-05）

用户运行100 kHz诊断后提供约第37～43秒的日志片段：DTMCS持续为 `0x7c71`，DMI扫描持续返回 `b`，等待周期逐渐增加后仍超时，最终 Target not examined yet。对应运行目录为 `artifacts/jtag-diagnostics/20261005-161501-839-100kHz`；metadata记录prepared_only=false、speed_khz=100和r1比特流文件哈希。用户粘贴片段不包含启动时首次DTMCS/DMI事务，不能确定何时进入Busy。

依据实际生成的 `SapphireSoc.v` 中 `logic_jtagLogic_dtmcs_captureData`：version=1，abits=7，idle=7，dmistat=3（Busy）。这与本版DTM结构相符，表明DTM寄存器能被读取；不等于CPU已可调试。该RTL在DMI请求pending时再次capture会报告Busy。外部ai_reset会保持debugCd复位并影响系统域请求处理。下一重点是首次请求、复位释放与跨域响应；不能由该片段直接判定某一根线或某个复位信号故障。

查明诊断工具的另一独立问题：`-l C:\...` 在厂商OpenOCD内部转成Tcl命令时未保护反斜杠，`\a`等被转义，导致日志文件打开失败，输出退回控制台。已用只执行echo/shutdown、不开适配器的官方OpenOCD命令复现。脚本改为 `-c 'log_output {C:/...}'`，并规范化配置路径；增加 `-OfflineLogCheck`。通过真实厂商工具离线验证，日志文件已创建且包含标记。该修复只解决日志保存，不声称解决DMI Busy。

请使用相同诊断命令再运行一次，约30秒后若仍超时则停止。日志现在写入新运行目录，可在第二终端使用脚本打印的Get-Content命令查看。保留完整openocd.log，而非只复制末尾重试片段，以确定首次DMCONTROL访问前后的状态。下一次无需改速率、超时或重新编译硬件。
