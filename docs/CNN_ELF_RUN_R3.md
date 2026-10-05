# r3：现有 ELF 已在 Ti60 上完成三组静态推理

对应阶段6子步骤：**恢复CPU调试、验证ELF下载、运行现有固件**。2026-10-05完成；阶段6整体验收未完成。

## 实测结论

官方 Efinity map/interface/pnr/pgm 全部通过，官方 FT232H JTAG 下载成功，OpenOCD examine/halt 正常。原ELF未经修改：SHA256 `694ff2a91c8a9f9811fb32af5479da1799ad969c633c587e5c9d4fba0132ff47`。

下载后执行 `reset halt`，再用GDB `compare-sections` 验证 `.init/.text/.init_array/.fini_array/.data` 五段全部 matched。随后从0x1000启动，三组静态输入均完成Invoke，最终PC=0x1068（官方启动代码的mainDone循环）。三次完整运行输出相同（含Windows PowerShell发布入口复测）：

| 输入编号 | 原golden输出 | 板上输出 | 严格逐值匹配 |
|---|---|---|---|
| 0 | [11, 0, -2] | [11, 0, -2] | 通过 |
| 1 | [-1, 79, -60] | [-1, 78, -60] | 未通过，第二项-1 |
| 2 | [1, -75, 63] | [1, -74, 63] | 未通过，第二项+1 |

状态为 `magic=0x47444231, stage=255, error=5, completed=3, passed=1`。三个argmax类别均一致，但不能将其记为INT8逐值一致性通过；没有修改golden或放宽固件判断。误差来源尚待分析，不能仅凭相差1就断言为舍入。

复测CLINT=96MHz，三次Invoke分别16671176、16665835、16665687 ticks，约173.66、173.60、173.60ms，静态Invoke约5.76次/秒；arena_used=84140字节。该耗时不包含摄像头采集、resize或Overlay，不等于完整视频FPS，尚未达到15FPS目标。

## 修复内容

1. Sapphire外部复位从AI准入门控改接全局复位，使官方调试域能独立连通；共享DDR的AI准入、abort、排空机制保留。
2. 官方BmbToAxi4Bridge输出AxSIZE=4，同时保留CPU字节地址，WSTRB指示字节通道。原窗口拒绝低4位非0的地址，导致每16字节只有首个32位字写入。r3归一化DDR节拍地址，保留数据/字节写使能；仍检查窗口、4KiB及溢出。
3. 不使用本CPU不支持的硬件断点。下载后增加官方 `reset halt` 清理启动状态，再回读校验、设置入口并运行，最后halt读状态。未加reset时曾在0x1000发生取指异常；reset后同一ELF正常执行。

新增四个32位字通道及非对齐边界回归通过；共享DDR隔离回归通过，含347次视频读取。r3系统时钟setup余量+0.792ns；JTAG两个跨域关系仍为-0.308/-1.297ns，hold关系均非负。这是用户授权的调试版本，时序未签核。

## 用户复现

使用 `deliverables/v0.5-ti60-debug-r3`（或同名zip解压）内的文件，不混用r1硬件。仅JTAG易失性下载，本次未写Flash。

1. 关闭占用下载器的OpenOCD/IDE调试会话。用Programmer的JTAG模式下载 `hardware/Ti60_AR0135.bit`；下载后退出编程操作。
2. 在解压目录打开PowerShell，运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\start-openocd.ps1
```

3. 看到 `Target successfully examined` 后，在同目录第二个PowerShell运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\start-gdb.ps1
```

脚本自动下载原ELF、reset halt、逐段比对，再运行10秒并读出 `cnn_debug_status`。若内存比对失败会停止；本版预期显示上述completed=3/passed=1并明确报告数值比较未通过，不代表OpenOCD又失联。不要按旧脚本设置 `thbreak`。

运行完成CPU停在结束处，结果保留供调试；JTAG bit及RAM内ELF断电后不保留。原host仍控制原图像链路；本版静态自检不发布实时firmware_ready，没有摄像头推理/分类Overlay。

发布入口已用 `powershell -NoProfile -ExecutionPolicy Bypass -File .\start-gdb.ps1` 实测，正常执行至三组结果后返回退出码2，表示严格数值比较未通过。

## 文件与证据

候选工程：`artifacts/evsoc-debug-lanes-r3/Ti60_AR0135.xml`。
板端记录：候选下 `board-run/load-verify.log`、`run-static.log`、`run-after-reset.log`、`static-result.json`、`program-jtag.log`、`openocd.log`。
历史排查：[r2复位及地址定位](CNN_ELF_RUN_R2.md)。原 `fpga-w.-codex` 目录未修改。

当前暂停点：ELF运行问题已解决；等待用户上板反馈，再分析±1数值差异、优化性能及接入实时图像。保持PR为Draft，不合并未验收的阶段6。
