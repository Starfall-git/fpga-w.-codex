# 摄像头—DDR3—HDMI 调试记录

本次修改针对根目录 `Ti60_Demo.xml` 工程。官方 demo 子目录未修改。用户确认：同一套硬件下载官方 demo 能显示摄像头图像，修改版为无信号/白屏。本次已完成编译和 bitstream 生成，尚未上板验证。

## 1. 已确认的回归：摄像头 XCLK 被一起删除

官方 `02-1_Ti60_OV5640_LCD-HDMI_1080P60/work_pt/peri_load.bak` 和该目录的 `outflow/Ti60_Demo.pt.rpt` 记录了以下连接：

```
clk_sys (96 MHz)
  -> lvds_pll / PLL_TR0
  -> CLKOUT2 / clk_27m（实际 16 MHz）
  -> cmos_xclk / GPIOR_16 / FPGA C12
  -> 摄像头连接器 P3.6 / CMOS_XCLK
```

修改前工程只剩 sys_pll、ddr_pll，没有 cmos_xclk GPIO；修改前引脚报告 C12 为 UNUSED。LVDS PLL 名字具有误导性，它也承担摄像头参考时钟。这个外设直连输出不需要在 RTL 中出现 `assign cmos_xclk`，因此仅检查顶层 Verilog 容易漏掉。

原理图 `Ti60-F225_Button_Board_V1.1_20230915.pdf` 第 2 页确认 P3.6 为 CMOS_XCLK，P3.5 为 CMOS_PCLK_3V3。PCLK 是摄像头输出，不能代替 FPGA 给摄像头的 XCLK。

恢复方案：新增 cam_pll，继续使用 PLL_TR0，沿用原 PLL 的 96 MHz 输入、48 MHz 本地反馈输出和 16 MHz 摄像头输出配置。仅保留必要两路输出，未恢复 MIPI 或 LVDS 显示通道。cam_pll_rstn_o 由 sys_pll_lock 驱动，其 lock 加入系统复位释放条件。

注意：缺少 XCLK 足以破坏摄像头采集，但不能单凭它解释显示器报告的全部“无信号”现象；HDMI 时序发生器本身不依赖摄像头帧数据。修复后若仍无信号，应执行下面的纯色隔离测试。

## 2. 分辨率不一致

虽然官方目录名带 1080P60，这份实际源码和配置是：

| 环节 | 修改前状态 | 本次修复 |
|---|---|---|
| OV5640 LUT 输出尺寸 | 1280×720 | 保持 |
| 顶层裁剪源/目标尺寸 | 1920×1080，横向按 2 字节/像素计数 | 1280×720 |
| DDR 读取帧字节数 | 4,147,200 | 1,843,200 |
| lcd_para 选中的时序 | 1280×720 | 保持 |
| 像素/串行时钟实际值 | 74.4 / 744 MHz | 保持原版配置 |

16 MHz XCLK 和 74.4 MHz 像素时钟均以实际 Interface Designer 报告为准，不以信号名、源码注释中的 27 MHz / 74.25 MHz 为准。

尺寸不一致是配置缺陷，但当前裁剪源和目标一样大，不能简单断言它必然裁掉全部数据或导致 HDMI 无信号。本次恢复统一的 720p 基线；1080p 应在基线恢复后统一修改传感器寄存器、显示时序、PLL、缓存长度和带宽配置。

## 3. 本次修改与验证

- `example_top.v`：摄像头 PLL 复位/锁定接口，720p 帧尺寸，LED 调试，默认关闭的 HDMI 纯色测试。
- `Ti60_Demo.peri.xml`：恢复 C12 的 cmos_xclk，新增 cam_pll。
- `Ti60_Demo.pt.sdc`：移除已删除 CSI/DSI/LVDS 时钟的有效约束，加入摄像头 PLL 时钟；保留 DDR 和 DVP 延时约束。
- `tools/check_video_config.py`：检查分辨率、摄像头时钟链、复位依赖，以及系统/DDR PLL 和四路 HDMI 配置与官方基线一致。
- 修改前上述三个文件备份位于 `tools/debug/before-fix/`。

Efinity 2026.1.132.3.9 实际运行结果：map、interface、pnr、pgm、bit/hex 导出全部 PASS。当前生成的 `outflow/Ti60_Demo.pt.rpt` 确认 cam_pll 输出 16 MHz，C12 映射到 cmos_xclk。

本次 `outflow/Ti60_Demo.timing.rpt` 的时钟关系汇总中，最小 setup slack 为 +0.153 ns，最小 hold slack 为 +0.026 ns。这是现有约束下的结果，不代替实际板级测量；原有 CDC false-path 和 IP 警告尚在，不声称消除了所有历史警告。

编译记录：`tools/debug/compile.log`。启动时环境中的 conda 自动初始化报错，但 Efinity 后续全部阶段通过且进程退出码为 0。

## 4. 上板步骤

1. 在 Efinity Programmer 中通过 JTAG 加载根工程最新的 `outflow/Ti60_Demo.bit`，不要误选官方子目录里的同名文件。
2. 若 JTAG 重配后不正常，完整断电再上电，并重新通过 JTAG 加载本次 bit，避免摄像头保留之前的状态。本次未烧写 Flash。
3. 观察 HDMI 是否出现图像，并记录 LED0～LED5。这里编号指 `led_o[0]`～`led_o[5]`，需按实物丝印对应。

| RTL 输出 | 默认 DEBUG_LEDS=1 的含义 | 正常逻辑状态 |
|---|---|---|
| led_o[0] | sys_pll_lock | 1 |
| led_o[1] | cam_pll_lock | 1 |
| led_o[2] | DDR cal_done | 1 |
| led_o[3] | DDR cal_pass | 1 |
| led_o[4] | OV5640 I2C 配置序列发送完毕 | 延迟后为 1 |
| led_o[5] | 摄像头 VSYNC 上升沿计数器 bit3 | 有连续帧时周期变化 |

表中为逻辑电平，不预设实物 LED 高/低有效。特别注意，原版 I2C 控制器推进 LUT 时没有用 ACK 限制，所以 LED4=1 **只表示配置序列走完，不证明摄像头应答成功**。LED5 有翻转也只证明 PCLK/VSYNC 在活动，不证明 RGB 数据正确。

4. 若摄像头无帧：先测 P3.6 的 16 MHz XCLK，再测 P3.5 的 PCLK、P3.3 的 VSYNC、P3.4 的 HREF，以及 P3.1/P3.2 的 SCL/SDA。使用地参考与板卡连接相符的探头。
5. 若仍 HDMI 无信号：把 `example_top.v` 开头的 `HDMI_TEST_PATTERN` 设成 1，重新完整编译并加载，期望看到洋红纯色。它在 TMDS 编码入口替换 RGB，绕过摄像头和 DDR 图像数据；仍依赖系统/DDR/摄像头 PLL 锁定及 HDMI 时序和引脚。
6. 纯色正常、摄像头模式异常：优先查 XCLK/PCLK、I2C ACK、DDR done/pass 和写入活动。纯色仍无信号：先看 PLL 指示和 rstn_pixel，再测 HDMI 时钟及确认实际加载的 bit 文件。测试完将 HDMI_TEST_PATTERN 恢复 0 并重新编译。

进一步用逻辑分析仪时，按时钟域分别观察：clk_sys 域的锁定、复位、I2C 状态、DDR 校准和 AXI 握手；cmos_pclk 域的 VSYNC/HREF/数据；clk_pixel 域的 lcd_hs/lcd_vs/lcd_de/lcd_request。不要用慢时钟直接采样高速 DVP 总线来判断数据质量。
