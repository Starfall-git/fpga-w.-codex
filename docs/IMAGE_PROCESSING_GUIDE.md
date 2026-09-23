# DDR 读出后的图像处理接口与 Sobel 接入说明

**V0.6更新**：ENABLE_SOBEL和BINARY_OUTPUT现为运行时输入，默认原图，旁路延迟也为六拍；当前接口与操作见 [V0.6说明](GUI_V06_GUIDE.md)。以下旧版本参数示例仅作为历史记录。

日期：2026-09-18；图像链路版本：V0.3，2026-09-21 更新动态阈值说明。当前实际工程目录为 `C:/Users/francis/Desktop/fpga-w.-codex`。

V0.4 已加入按键/UART 实时阈值控制，详见 [上位机与串口接口说明](../host/README.md)。下面的图像流结构仍然适用，阈值已从参数改为像素域输入端口。

## 1. 本次数据路径

```text
OV5640 DVP -> 摄像头裁剪 -> AXI 写入 -> DDR3
                                            |
                                     AXI 读出 / 读 FIFO
                                            | RGB565，lcd_request 请求
                                   顶层 RGB565 -> RGB888
                                            |
                                        lcd_driver
                                            | RGB888 + HS + VS + DE
                                    video_processing
                                      灰度转换（1级）
                                      3x3窗口（2级）
                                      Sobel运算（3级）
                                            | processed_rgb/hs/vs/de
                                         rgb2dvi
                                            |
                                   HDMI串行器 -> 显示器
```

处理模块接在 `lcd_driver` 之后，是因为这里已有完整的有效像素和显示同步信号。物理数据仍来自 DDR 读 FIFO。`lcd_request`、送给 AXI 的 `~lcd_vs` 保留原来的连接；不得改成处理之后的信号，否则会把算法延迟引入 DDR 取数和读帧切换。

## 2. 改了哪些文件

| 文件 | 变化 |
|---|---|
| `example_top.v` | 顶部追加 V0.3 第 8～12 项记录；新增 Sobel 参数；实例化 `u_video_processing`；HDMI 的四路视频输入改为 `processed_*` |
| `src/isp/video_processing.v` | 新增 RGB 流封装、灰度转换和原图旁路 |
| `src/isp/video_window3x3.v` | 新增两个灰度行缓存及 3×3 窗口，供邻域算法复用 |
| `src/isp/video_sobel.v` | 新增梯度、幅度、二值/灰度输出流水线 |
| `Ti60_Demo.xml` | 添加三个新 RTL 文件到 Efinity 工程源文件清单 |
| `testbench/video_processing_tb.sv` | 新增六组参数配置的逐拍 RTL 检查 |
| `tools/run_sobel_sim.py` | 生成独立图像参考结果并运行 ModelSim |

源码的新增/修改位置均带 `/* V0.3 ... */` 或模块头块注释，顶层 HDMI 旧连接保留在块注释内。修改前顶层和工程配置备份在 `tools/debug/before-sobel/`。

本次没有增加顶层物理引脚、PLL 或时钟域，因此不需要修改引脚绑定和 SDC。每次添加算法后仍需重新检查布局布线时序。

## 3. 使用与调参

顶层 `example_top` 的参数默认如下：

```verilog
parameter HDMI_TEST_PATTERN = 0,
parameter ENABLE_SOBEL = 1,
parameter SOBEL_BINARY = 1,
parameter UART_BAUD = 115200
```

| 设置 | 显示效果 |
|---|---|
| `ENABLE_SOBEL=1, SOBEL_BINARY=1` | 默认黑底白色边缘 |
| `ENABLE_SOBEL=1, SOBEL_BINARY=0` | 灰度梯度强度，超过 255 饱和为白色 |
| `ENABLE_SOBEL=0` | 原始摄像头图像，便于比较 |
| `HDMI_TEST_PATTERN=1` | HDMI 洋红纯色，优先于算法输出 |

二值模式中，阈值越小，细节和噪声越多；阈值越大，保留的强边缘越少。可以依次尝试 64、128、256。V0.4 的 `SOBEL_THRESHOLD` 是 12 位运行时输入，复位值 128，由双键或 UART 调节，在场消隐更新，不需要重新生成 bit。其他顶层参数仍是编译时常量。

Sobel 输入先转换为 `Y=(R+2G+B)/4`，这是节省硬件的近似灰度转换。RGB565 到 RGB888 的扩展仍沿用原工程：R/B 低 3 bit、G 低 2 bit 补零。

```text
Gx = (p02 + 2*p12 + p22) - (p00 + 2*p10 + p20)
Gy = (p20 + 2*p21 + p22) - (p00 + 2*p01 + p02)
M  = |Gx| + |Gy|
```

Gx/Gy 使用 11 bit 有符号数；M 使用 12 bit 无符号数。二值输出比较的是未经归一化的 M，不是截断后的 8 bit 数值。灰度输出为 `min(M,255)`，不执行开方。

## 4. 通用 RGB 流接口

| 信号 | 位宽 | 含义 |
|---|---:|---|
| `clk` | 1 | 本工程使用 `clk_pixel`，实际 PLL 报告为 74.4 MHz |
| `rst_n` | 1 | 低有效复位，接 `rstn_pixel` |
| `rgb_i / rgb_o` | 24 | `{R[7:0],G[7:0],B[7:0]}` |
| `hs_i / hs_o` | 1 | 行同步，保留输入极性 |
| `vs_i / vs_o` | 1 | 场同步，本工程低有效 |
| `de_i / de_o` | 1 | 高电平表示本拍像素有效 |

协议约束：

1. 每个 `de_i=1` 的时钟接收一个像素，每行正好 `IMAGE_WIDTH` 个有效像素。
2. 像素、HS、VS、DE 使用同一个时钟；此接口没有 ready，也不能暂停上游。算法必须能连续每拍处理一个像素。
3. RGB 运算增加多少级寄存器，HS/VS/DE 就同步增加多少级；消隐期间也必须推进这些控制信号。
4. 行缓存地址只在有效像素时推进，场同步有效时复位坐标。帧间必须有 VS 脉冲；不能用全帧恒定的 VS。
5. DE 表示输出栅格中的有效像素。窗口尚未填满时仍保留 DE，将 RGB 输出为黑色，保持一帧的有效像素数量。
6. 本模块坐标为 12 bit，支持宽度 3～4095；改变分辨率时还要同步修改传感器、DDR 帧长度、显示时序及 PLL。仅修改 `IMAGE_WIDTH` 不会改变系统分辨率。

## 5. 延迟与边界

Sobel 路径共六级寄存器：灰度 1 级、行缓存同步读 1 级、窗口组合寄存 1 级、梯度 1 级、幅度 1 级、输出 1 级。

若像素在上升沿 n 被第一级采样，则最终 RGB、HS、VS、DE 在上升沿 n+5 后同时出现；这对应六级寄存器，不要额外再给 HDMI 同步信号增加延迟。RTL 仿真逐拍验证了这一关系。旁路为组合直通，零级延迟；切换参数后总延迟随之改变，但数据与同步始终一起变化。

窗口是实时、只使用已到达像素的窗口：输入坐标 `(x,y)` 对应窗口范围 `(x-2,y-2)..(x,y)`，Sobel 中心在 `(x-1,y-1)`。本版把计算结果显示在输出栅格的 `(x,y)`，因此相对原图，边缘位置向右、向下各偏移一像素。前两行、前两列没有完整窗口，输出黑色；不额外缩短 DE，也不输出额外行列来补齐右边和底边。

这是明确的边界约定，不是只靠延迟 HS/VS/DE 就能消除的坐标偏移。若以后要求原图和边缘逐像素叠加，需为原图配套延迟/坐标映射；若要求居中卷积且四周补零，则需增加行级调度、边界补像素和相应缓存。本版未实现这两种模式。

行缓存不整体复位，以便推断块 RAM。每帧前两行重新填充缓存，`window_valid` 屏蔽旧帧数据；每行前两列负责冲掉横向移位寄存器中的旧列数据。

## 6. 下次如何加入高斯滤波

建议把新算法的外部接口做成与 `video_processing` 相同的 RGB/HS/VS/DE 输入输出，然后在 `video_processing.v` 内串联。顶层继续只连接一个处理封装。

例如要先高斯平滑，再 Sobel：

```text
video_processing 输入
       -> video_gaussian（未来新增模块）
       -> 现有灰度寄存器
       -> video_window3x3
       -> video_sobel
       -> video_processing 输出
```

以下是**未来新增模块的接线示例**，`video_gaussian` 尚未提供实现，不能直接加入当前工程编译：

```verilog
wire [23:0] gauss_rgb;
wire gauss_hs, gauss_vs, gauss_de;
video_gaussian #(.IMAGE_WIDTH(IMAGE_WIDTH)) u_gaussian (
    .clk(clk), .rst_n(rst_n),
    .rgb_i(rgb_i), .hs_i(hs_i), .vs_i(vs_i), .de_i(de_i),
    .rgb_o(gauss_rgb), .hs_o(gauss_hs), .vs_o(gauss_vs), .de_o(gauss_de)
);
```

加入后，把当前灰度转换中的 `rgb_i` 替换为 `gauss_rgb`，把 `gray_hs/gray_vs/gray_de` 的输入分别替换为 `gauss_hs/gauss_vs/gauss_de`。必须一起改，不能让灰度像素经过高斯处理而同步信号绕过高斯。

如果只做灰度高斯，资源更省的方式是放在现有灰度转换之后：

```text
灰度 -> 第一个 3x3 窗口 -> 高斯加权求和 -> 第二个 3x3 窗口 -> Sobel
```

灰度 3×3 高斯可复用 `video_window3x3`，计算：

```text
        1 2 1
K =     2 4 2   /16
        1 2 1
G = (p00+2*p01+p02+2*p10+4*p11+2*p12+p20+2*p21+p22) >> 4
```

最大加权和为 4080，应使用至少 12 bit 再右移 4 位。高斯输出是一张新的图像，Sobel 需要这张新图像的邻域，不能直接复用高斯输入的同一个窗口当成高斯输出的 Sobel 窗口。两个因果邻域模块串联还会累积边界和坐标偏移，应先确定边界策略。

新增算法的修改顺序：

1. 在 `src/isp/` 新增算法文件，模块头用块注释说明算法、延迟、参数和边界约定。
2. 在 `video_processing.v` 中串联 RGB/HS/VS/DE；要支持选择时，可增加编译期参数并在顶层传入。
3. 顶层汇总追加新的日期/版本段，编号从 13 继续；每处修改旁保留块注释说明。
4. 在 `Ti60_Demo.xml` 的 `design_info` 中增加新源文件，或在 Efinity GUI 中添加。
5. 只做像素域内部算法通常不需要新物理端口。若要按键切换或 UART 配置，才增加控制信号和必要约束，并处理跨时钟域及帧边界更新。
6. 运行逐拍仿真，检查算法数值、HS/VS/DE 对齐、消隐、每行长度、连续帧、复位。再完整编译并检查 RAM 用量和时序裕量。

## 7. 验证结果与上板

本次 ModelSim 对以下尺寸分别验证了六种配置：二值阈值 128、灰度强度、阈值 0、阈值 2047、旁路、高有效 VS。

| 有效区域尺寸 | 检查时钟数 | 目的 |
|---|---:|---|
| 8×6 | 1,143 | 小图像逐拍参考比较 |
| 1280×8 | 115,887 | 实际 1280 像素行长度和 RAM 地址换行 |
| 8×720 | 95,391 | 720 行及跨帧状态 |
| 3×4 | 616 | 最小支持宽度 |

测试图包括纯黑/白、水平/垂直阶跃、斜边、棋盘、单点、阈值等值、随机 RGB；另有随机消隐数据、连续不同帧和帧中复位。参考值在 Python 中直接从二维图像计算，不复用 RTL 的行缓存实现。以上不是摄像头/DDR/HDMI 的整板仿真，也没有声称已完成真实上板验证。

```powershell
python tools/run_sobel_sim.py
python tools/run_sobel_sim.py --width 1280 --height 8
python tools/run_sobel_sim.py --width 8 --height 720
python tools/run_sobel_sim.py --width 3 --height 4
```

需要 ModelSim 的 `vlib/vlog/vsim` 在 PATH，或设置环境变量 `MODELSIM_BIN` 指向其程序目录。输出保存在 `tools/debug/sobel_sim_*`。

Efinity 2026.1：综合、接口检查、布局布线、bit 导出全部 PASS。整个工程使用 50 个 EFX_RAM10，其中新增处理模块使用 4 个；在现有约束下，时钟关系汇总最小 setup slack 为 +0.153 ns、最小 hold slack 为 +0.014 ns。沿用的历史约束和 IP 警告仍需按板级情况评估。

V0.3 的 Sobel 基线保存在 `outflow/Ti60_Demo_sobel_720p.bit`，日志为 `tools/debug/compile-sobel.log`。V0.4 当前 `outflow/Ti60_Demo.bit` 已含 UART 控制，同内容另存为 `outflow/Ti60_Demo_uart_threshold_720p.bit`，日志为 `tools/debug/compile-uart.log`。可通过 JTAG 加载观察黑底白边；若画面噪声太多，通过按键或 GUI 提高阈值；若需要先核对摄像头链路，将 ENABLE_SOBEL 改为 0 后重新编译。
