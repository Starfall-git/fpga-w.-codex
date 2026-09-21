# VF-Ti60 串口图像控制台（V0.4）

2026-09-21。当前已实现：串口设置/查询 Sobel 阈值，保留板上双键调节。上下翻转、自定义裁剪、缩放目前完成 GUI、参数校验和命令接口预留，尚未实现 FPGA 图像变换。

## 1. 启动和上板

在工程根目录运行（Python 3.10+，需要 Tkinter；当前已用本机 Python/Tk 9.0 验证）：

```powershell
python -m pip install -r host/requirements.txt
python -m host.gui
```

也可双击 `host/start_gui.bat`。本机测试使用 `D:/python/python.exe`；若系统 `python` 指向其他环境，使用这个完整路径运行上述命令。仅体验界面：`python -m host.gui --demo`，再点击“连接”；界面会明确显示“模拟 · 未连接硬件”。模拟模式不会打开串口。

1. 下载 `outflow/Ti60_Demo_uart_threshold_720p.bit`，这是本次已编译的控制版本。
2. 连接串口，选择“串口硬件”、正确 COM 口，默认 **115200 / 8 数据位 / 无校验 / 1 停止位 / 无流控**。
3. 点击“连接”，收到 FPGA 协议/能力回读后，阈值应用按钮才可用。初始阈值为 128。
4. 在输入框键入 64、128、256 等整数，点击“确认并应用”或按 Enter。编辑文字本身不会发送。右侧只显示应答确认的值。
5. 阈值范围是 **0～4095**。阈值越高保留边缘越少，过大可能全黑；灰度强度模式 `SOBEL_BINARY=0` 不使用二值阈值。当前默认 `ENABLE_SOBEL=1, SOBEL_BINARY=1`。
6. 按 `key_data[0]` 加 1，按 `key_data[1]` 减 1；低有效，按一次一步，长按不连发，上下限饱和。GUI 默认每 1.5 秒查询，因此也能看到板上按键变化。

项目现有外围绑定如下，本次没有改变 UART 引脚：

| 逻辑端口 | FPGA 管脚 | GPIO | 工程电平 |
|---|---|---|---|
| `uart_rx_i` | F10 | GPIOT_N_16 | 1.8 V LVCMOS |
| `uart_tx_o` | E10 | GPIOT_P_16 | 1.8 V LVCMOS |

以上来自 `Ti60_Demo.peri.xml` 和本次 `outflow/Ti60_Demo.pinout.csv`，**是 FPGA 管脚，不是排针脚号**。板载 USB 转串口是否接到这两个信号须按实际板卡原理图核对；若使用外接 USB-TTL，TX 接 FPGA RX、RX 接 FPGA TX、共地，并通过适合 1.8 V 的电平接口连接，不能直接按 3.3 V/5 V TTL 接入。更换引脚请在 Efinity Interface Designer 同步修改并重新编译。

GUI 串口只传控制命令，不传图像；图像继续经 HDMI 显示。不能直接在串口助手输入字符串 `256`，本协议使用二进制帧。

## 2. 分层与改动位置

| 文件 | 本次变化 |
|---|---|
| `example_top.v` | 顶部追加 V0.4 编号 13～18；新增 `UART_BAUD`；修正按键向量声明；旧按键阈值逻辑完整保留在块注释；实例化 `u_image_control` |
| `src/control/uart_rx.v`、`uart_tx.v` | 新增 UART 8N1 接收/发送，RX 双级同步、起始位确认、停止位检查 |
| `src/control/key_debounce.v` | 新增双级同步和按下/释放双向 20 ms 消抖 |
| `src/control/threshold_cdc.v` | 新增多位阈值邮箱及请求/确认握手，场消隐提交 |
| `src/control/uart_image_control.v` | 新增 CRC/命令解析、按键与串口仲裁、已生效值回读 |
| `src/isp/video_processing.v`、`video_sobel.v` | 保留你们已改好的动态阈值端口，补充输入须处于像素域的说明 |
| `Ti60_Demo.xml` | 登记 5 个新增控制模块 |
| `host/protocol.py` | 与串口无关的编解码、CRC、命令编号和参数校验 |
| `host/client.py` | 串口打开/关闭、序号匹配、超时处理、状态查询和功能 API |
| `host/gui.py` | GUI、后台通信线程、能力控制、预留功能草稿和通信记录 |
| `testbench/uart_control_tb.sv`、`tools/run_uart_sim.py` | 新增 UART 物理位流、CDC、按键和实际 Sobel 阈值影响的集成测试 |
| `host/test_host.py` | 新增协议错误处理及 GUI 操作测试 |
| `testbench/video_processing_tb.sv` | 将原参数阈值实例更新为运行时阈值输入 |

改动前的四个现有源/工程文件保存在 `tools/debug/before-uart/`。RTL 注释使用 `/* ... */`，XML 使用其合法的 `<!-- ... -->` 注释。

## 3. 顶层接口与生效时机

```text
Python GUI → SerialClient → UART RX → 命令解析 ─┐
                                              ├→ desired（clk_sys）
key_data[1:0] → 同步/消抖 → 加减 ────────────────┘
  → 稳定邮箱 + 请求翻转 → 两级同步 → 场消隐提交（clk_pixel）
  → SOBEL_THRESHOLD → video_processing → video_sobel
  → 确认翻转返回 → applied（clk_sys）→ UART TX → GUI 已确认值
```

顶层接法：

```verilog
wire [11:0] SOBEL_THRESHOLD;
uart_image_control #(
    .CLOCK_HZ(CLOCK_MAIN), .BAUD(UART_BAUD),
    .DEBOUNCE_CYCLES(CLOCK_MAIN/50)
) u_image_control (
    .clk(clk_sys), .rst_n(rstn_sys),
    .uart_rx_i(uart_rx_i), .uart_tx_o(uart_tx_o),
    .key_data(key_data),
    .pixel_clk(clk_pixel), .pixel_rst_n(rstn_pixel),
    .frame_blank_i(!processed_vs),
    .threshold_pixel_o(SOBEL_THRESHOLD)
);
// u_video_processing 新阈值端口：.SOBEL_THRESHOLD(SOBEL_THRESHOLD)
// 内部 u_sobel 的阈值端口：.THRESHOLD(SOBEL_THRESHOLD)
```

`clk_sys` 为 96 MHz。当前 HDMI VS 低有效，所以 `!processed_vs` 是场同步消隐窗口；选择处理后的 VS 避免改动时流水中还有上一帧有效像素。若以后改变 VS 极性，必须同时修改这一条件。

12 位数据不能简单逐位加两级寄存器直接跨域：本实现从请求到确认期间保持邮箱不变，只同步请求/确认控制信号。像素域在场消隐一次性更新，系统域收到确认后才认为已生效。两个域复位必须共同来自现有 PLL 锁定条件，不支持任意单独复位一侧。

串口设置等待提交时忽略新按键事件；其他时间按键更新目标值。如果已有按键值正在传输，先完成它，再提交串口目标值，最后回复。GET 查询返回已确认值，不把待处理目标值当成已生效值。

若请求值与当前值相同，可以直接确认。正常显示情况下新值约下一帧生效。若场同步停止且不处于提交窗口，新的设置会继续等待，GUI 超时仅表示“是否生效未知”；恢复视频时序后再查询。当前 FPGA 不缓存并发命令，不能连续灌入多个设置包。

## 4. 二进制协议 V1

所有帧固定 13 字节。多字节整数均为小端。

| 字节位置 | 字段 | 含义 |
|---|---|---|
| 0～1 | A5 5A | 帧头 |
| 2 | SEQ | 0～255 序号，响应回显 |
| 3 | CMD | 命令号；应答为请求 CMD OR 0x80 |
| 4～11 | D0～D7 | 固定 8 字节载荷 |
| 12 | CRC8 | 覆盖 SEQ、CMD、D0～D7；poly=0x07，init=0，非反射，xorout=0 |

CRC 标准检查向量：ASCII `123456789` → `0xF4`。

| CMD | 请求载荷 | 当前状态 |
|---|---|---|
| 0x01 查询 | 全 0 | 已实现 |
| 0x10 阈值 | uint16 阈值 + 6 字节 0；范围 0～4095 | 已实现 |
| 0x20 上下翻转 | D0 为 0/1，其余 0 | 预留 |
| 0x21 裁剪 | uint16 x、y、width、height | 预留；GUI 按输入 1280×720 校验 |
| 0x22 缩放 | uint16 分子、分母 + 4 字节 0 | 预留；GUI 限制 0.25～4 倍 |

所有响应载荷统一为：`[状态, 当前阈值低字节, 当前阈值高字节, 协议版本, 能力位, 0, 0, 0]`。

状态：0 成功、1 CRC 错误、2 参数错误、3 未实现命令。能力位：bit0 阈值、bit1 翻转、bit2 裁剪、bit3 缩放；当前 FPGA 只返回 `0x01`。GUI 据此禁用后三种功能的发送按钮。它们的草稿预览不发送串口。

一次只发一个请求，等待匹配 SEQ/CMD 且 CRC 正确的应答；FPGA 处理/发送期间的额外命令会被丢弃。字节间停顿超过 10 ms 将丢弃半帧，故请一次 write 完整发送 13 字节。错误停止位也重置接收解析。主机默认等 1 秒，不自动重试；断线/超时后先回读确认，不能仅凭“写入串口成功”判断设置已生效。

纯 Python 接口，供以后接入其他上位机或自动化：

```python
from host.client import SerialClient

device = SerialClient("COM5", baud=115200)
try:
    print(device.get_status())
    print(device.set_threshold(256))  # 等 FPGA 实际应用确认后才返回
    # 下列接口已预留；当前能力不足会拒绝发送：
    # device.set_flip(True)
    # device.set_crop(100, 50, 640, 360)
    # device.set_zoom(3, 2)
finally:
    device.close()
```

## 5. 后续功能接入步骤

1. 在 `uart_image_control.v` 对应命令分支中校验参数，写入该功能的影子配置寄存器。裁剪四个值应作为完整配置一起提交，不能分别生效。
2. 像阈值一样，把配置通过稳定邮箱和请求/确认握手送到实际使用它的时钟域；在该功能安全的帧边界提交。只有真正生效才发成功应答。
3. 接好数据路径并验证后，再置位响应中的对应能力位。GUI 将开放相应发送按钮；Python API 和编码无需另改。
4. 现有 V1 响应只回读阈值，后三种功能尚无配置回读。实现时应新增专用查询命令，或设计 V2 状态格式并同步修改 `DeviceStatus`、GUI、RTL 和测试，不应把草稿当成硬件回读。
5. 上下翻转一般需要改变帧缓存读取行地址顺序；串行输出末端没有整帧缓存时，单靠组合像素逻辑不能翻转整幅图。需协调 DDR 地址、读突发和帧切换。
6. 裁剪/缩放需先约定“输出保持 1280×720，空余区域如何填充”或重设输出时序。目前只预留源图裁剪坐标及缩放比，没有实现插值算法和显示映射。不能只缩短 DE 而继续按原 DDR 请求取数。
7. 高斯等固定分辨率滤波可继续串接 RGB/HS/VS/DE 流，所有同步信号与像素延迟一致，接口详见 `docs/IMAGE_PROCESSING_GUIDE.md`。处理模块不应反向改变现有 `lcd_request`、DDR 原始帧同步。

## 6. 本次验证与限制

已完成：

- Efinity 2026.1 全流程 map/interface/pnr/pgm/bitstream 导出通过。最终报告列出的 setup/hold slack 均为正；系统域 setup 4.424 ns、像素域 setup 10.111 ns。
- ModelSim UART 集成：独立位流驱动/采样、响应 CRC、错误参数/CRC/命令、半帧超时、停止位错误、帧边界提交、异步像素时钟、按键抖动/长按/上下限/仲裁、复位；并验证阈值 128→256 使固定梯度的 Sobel 输出由白变黑。
- Sobel 回归：8×6 共 1,143 拍，1280×8 共 115,887 拍；检查二值/强度/边界阈值/旁路/VS 极性。
- Python 8 项测试通过，包括分片/噪声/错误 CRC/过期序号恢复、超时不重试、未实现功能不发送、GUI 模拟连接/输入/确认/回读/断开。

复现命令：

```powershell
python -m unittest host.test_host -v
python tools/run_uart_sim.py
python tools/run_sobel_sim.py --width 1280 --height 8
```

仿真需 ModelSim，必要时设置 `$env:MODELSIM_BIN`。编译日志为 `tools/debug/compile-uart.log`，仿真日志在 `tools/debug/uart_sim/` 和 `tools/debug/sobel_sim_*/`。

本次未通过真实 COM 口与板卡联调，也未替你下载到板卡；bitstream、布线时序通过不能代替实际电气连接和显示效果验证。若 GUI 连接超时，先核对下载的是否为本版 bit、COM 口、RX/TX 和电平，再用通信记录检查请求/响应。
