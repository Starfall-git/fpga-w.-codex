# V0.5：上位机实时几何变换与 DDR 读出接口

**当前V0.6说明见 [快捷交互与模式控制](GUI_V06_GUIDE.md)**：缩放已扩展至10%～500%，默认显示原图；翻转点击提交，阈值和百分比回车提交，“默认”恢复全部图像选项并保留阈值。下文保留V0.5架构和历史操作记录。

2026-09-22。实际工程目录：`C:/Users/francis/Desktop/fpga-w.-codex`。本版实现左右/上下翻转、裁剪、放大/缩小，保留Sobel阈值串口及双键调节。帧冻结、回放、对比留待后续设计。

## 1. 上板与显示方式

下载 `outflow/Ti60_Demo_transform_720p.bit`。在工程根目录运行：

```powershell
python -m pip install -r host/requirements.txt
python -m host.gui
```

本机测试解释器为 `D:/python/python.exe`。也可双击 `host/start_gui.bat`。无硬件演示运行 `python -m host.gui --demo` 后连接模拟设备；模拟回读不代表FPGA生效。

串口为 **115200、8N1、无流控**。RX F10、TX E10为FPGA封装管脚，工程电平是 **1.8 V LVCMOS**；不是排针脚号。板载USB转串口线路需按实际原理图核对，外接USB-TTL须通过匹配1.8V的电平接口、RX/TX交叉且共地。

GUI操作：

- 上下/左右翻转是两个独立复选框，可同时开启，选择后点击“应用到FPGA”。
- 裁剪输入X、Y、宽、高。原点为原始1280×720帧左上角，不受当前翻转和倍率影响。区域必须完全在源图内，宽高至少1。
- 倍率可选0.25、0.5、1、1.5、2、3、4。底层API还支持分子/分母均为1～16、结果为0.25～4的有理数倍率。
- “恢复全图 / 1倍 / 不翻转”依次执行三次帧提交，不修改Sobel阈值。这不是一次原子操作。
- 硬件已确认配置单独显示，默认每1.5秒回读；回读不覆盖正在输入的草稿。输入/勾选本身不会发送，必须点击应用。

**顺序：源图裁剪 → 在裁剪区域内翻转 → 最近邻等比例缩放 → 居中放到1280×720画布。** 缩小四周补黑，放大超出屏幕时居中截取；裁剪不会自动铺满屏幕。

| 设置 | HDMI结果 |
|---|---|
| 全图、1倍、不翻转 | 原有几何尺寸及方向 |
| 全图、0.5倍 | 中央640×360图像，四周黑边 |
| `(320,180,640,360)`裁剪、1倍 | 中央640×360裁剪区域 |
| 同样裁剪、2倍 | 裁剪区域放大至1280×720 |
| 全图、2倍 | 原图中间区域放大显示 |
| 上下和左右均开 | 在裁剪区域内等效旋转180度 |

尺寸向下取整；居中差值为奇数时，右/下多1像素。缩放后宽高不足1像素会被拒绝。例如1×1裁剪不能再缩小至0.25倍。错误设置不会覆盖已应用配置。

默认Sobel仍开启，显示的是**变换后的边缘图**。黑边与图像交界也可能产生Sobel边缘；若需验证原始彩色几何效果，可将顶层 `ENABLE_SOBEL=0` 后重编译。最近邻放大可能呈像素块、缩小可能有锯齿；本版未加入双线性插值或缩小前低通滤波。UART只传控制数据，图像仍由HDMI显示。

## 2. 修改清单

顶层追加V0.5编号 **19～24**，RTL新增/替换位置带 `/* ... */` 注释。备份在 `tools/debug/before-transform/`，官方demo未修改。

| 文件 | 变化 |
|---|---|
| `example_top.v` | 选择 `C_TRANSFORM=1`；新增98位配置/请求/确认/诊断线；接入DDR真实RRESP；追加变更汇总 |
| `src/axi/axi4_ctrl.v` | 新增几何读出分支；原顺序读出保留于 `Gen_Legacy_Reader`；保留写端与四帧调度；新读出器负责动态ARLEN/RREADY |
| `src/isp/axi_transform_reader.v` | 源行读取、跨4KB突发拆分、双显示行缓存、最近邻映射、帧切换、缺行补黑 |
| `src/isp/unsigned_divider.v` | 32拍迭代除法器，在配置/行准备阶段使用 |
| `src/control/uart_image_control.v` | 实现几何命令、参数校验、配置邮箱、硬件回读和能力声明 |
| `Ti60_Demo.xml` | 添加2个新RTL文件；未改动引脚或PLL |
| `host/protocol.py` | 双向翻转编码、GET_CONFIG、Geometry已确认配置类型 |
| `host/client.py` | 设置后回读核对、恢复默认、模拟几何接口 |
| `host/gui.py` | 开放几何按钮、双方向复选框、实际配置和诊断回读 |
| 新增testbench和仿真脚本 | 像素参考、AXI背压/帧切换、Python串口帧测试 |

若手动切回 `C_TRANSFORM=0` 的原顺序读出，还须把UART的 `TRANSFORM_ENABLE=0`，避免宣称支持未接入的功能。

## 3. 数据路径与缓存

```text
OV5640 → 原写FIFO/AXI写端 → DDR3四帧缓冲
                               ↓ 反算所需源行
                     AXI突发读取完整RGB565源行
                               ↓
                     source_ram：128bit × 160
                               ↓ 水平翻转/最近邻映射
                    display_ram：16bit × 1280 × 2
                               ↓ 像素时钟域同步读出
                  原lcd_driver → 原Sobel → 原HDMI
```

实际AXI用户时钟 `w_ddr3_ui_clk=clk_sys=96MHz`，不是DDR PHY的192MHz核心时钟；像素时钟74.4MHz。一行1650拍、有效1280拍，行周期约22.18微秒。

每个目标行读取一次对应源行，再生成1280个输出像素。水平坐标采用整数商/余数累加，非整数倍率也不会逐像素除法。竖直坐标每行计算一次；放大时可能重复读取源行，缩小时跳过源行。

新增缓存逻辑容量为20,480bit源行和40,960bit双显示行，共61,440bit，没有新增片内整帧缓存。最坏每显示帧读取720个源行，约110.6MB/s（按60帧/秒），另有原摄像头写流量。实际仲裁延迟仍需上板检查。

读突发最多128个128bit beat，并在4KB边界拆分。源行2560字节，不能一律发固定128拍突发。只允许一笔在途，ARVALID受阻时保持地址/长度，RLAST完成后继续。

原 `R0_FIFO_16` 采用大端宽度转换，首像素位于AXI `[127:112]`；新读出保持此顺序。像素域仍通过提前一拍的 `lcd_request` 读取RGB565，后级 `lcd_driver` 和Sobel同步信号关系不变。

## 4. 顶层连接、帧边界与跨域

几何配置共98位：`[1:0]` 翻转（bit0上下、bit1左右）；`[17:2]` X；`[33:18]` Y；`[49:34]`宽；`[65:50]`高；`[81:66]`分子；`[97:82]`分母。

```verilog
// example_top内连接UART控制器与axi4_ctrl的新端口：
wire [97:0] transform_geometry;
wire transform_toggle, transform_ack;
wire [1:0] transform_faults;
// UART: geometry_o / geometry_toggle_o -> 配置和请求
// AXI : geometry_i / geometry_toggle_i <- 同一组线
// AXI : geometry_ack_o -> UART geometry_ack_i
// AXI : transform_faults_o -> UART transform_faults_i
```

UART验证命令后发布完整配置快照，并翻转请求位；收到确认前保持数据稳定。DDR读出器在显示帧开始时采样，预计算缩放尺寸、居中偏移和坐标步长；完成后返回确认，UART才更新 `geometry_applied` 并发送成功应答。

UART/AXI当前同为96MHz，仍保留配置邮箱握手；像素域帧/行请求通过双级同步的toggle往返跨域。各域必须一起复位，不能任意单独复位一侧。

帧切换先排空旧行与在途AXI突发，再发 `frame_switch_o` 接入原 `r_rframe_inc`，等待原四帧调度更新读索引后采样基址。写端继续避让当前读帧，不会逐行切换到不同摄像头帧。

像素域丢弃迟到旧帧行，一行开始时锁定该行是否可用。未及时完成则整行补黑，不会中途切入迟到像素；DDR错误行同样补黑。诊断位0为出现过缺行、位1为出现过AXI响应/长度错误，保持至FPGA复位。初始化等待DDR就绪也可能留下缺行历史，不等于当前持续故障。

## 5. 串口协议增量

保持V1固定13字节：`A5 5A SEQ CMD D0 D1 D2 D3 D4 D5 D6 D7 CRC8`。CRC覆盖SEQ到D7，poly07/init00、非反射、xorout00；多字节小端。主机一次一个请求，默认等1秒，不自动重试；FPGA字节间超时10ms。超时意味着是否生效未知，应先回读确认。

| CMD | 请求载荷 | 应答 |
|---|---|---|
| 01 | 全0 | 原状态 |
| 10 | uint16阈值+6字节0 | 原状态，阈值0～4095 |
| 20 | D0 bit0上下、bit1左右，其余0 | 标准状态 |
| 21 | uint16 X、Y、宽、高 | 标准状态 |
| 22 | uint16分子、分母+4字节0 | 标准状态 |
| 02 | D0页号0～3，其余0 | 专用配置页 |

标准载荷：`[状态,阈值低,阈值高,版本1,能力0F,0,0,0]`。状态0成功、1CRC错误、2参数错误、3未实现；能力bit0阈值、bit1双向翻转、bit2裁剪、bit3缩放。应答CMD等于请求CMD OR 80。

02应答：`[状态,页号,6字节页数据]`。

| 页 | 六字节页数据 |
|---|---|
| 0 | 翻转标志、诊断标志、0、0、0、0 |
| 1 | X低、X高、Y低、Y高、0、0 |
| 2 | 宽低、宽高、高低、高高、0、0 |
| 3 | 分子低、分子高、分母低、分母高、0、0 |

GUI单通信线程，客户端加锁使四页查询不与本进程设置交错。当前只有UART写几何参数，按键只调阈值；未来加入第二个几何写入者时，需要快照编号或一次性冻结查询快照。

```python
from host.client import SerialClient
board = SerialClient('COM5')
try:
    board.get_status()
    board.set_flip(True, True)          # 上下、左右
    board.set_crop(320,180,640,360)
    board.set_zoom(2,1)
    print(board.get_geometry())
    board.reset_geometry()
finally:
    board.close()
```

旧V0.4 bitstream能力仅01，新GUI仍可调阈值但禁用几何按钮。几何功能须下载V0.5 bitstream。

## 6. 验证与复现

- Efinity 2026.1全流程通过，STA列出的setup/hold裕量均为正。系统域setup 3.814ns、像素域9.156ns、DDR核心域1.027ns；未放宽时钟目标。
- 1280×8：62组参数、634,880个像素与独立Python整数公式一致，覆盖双向翻转、非对齐裁剪、最小区域和有理数倍率。
- 1280×720：4帧、3,686,400像素与参考一致，96MHz AXI、74.4MHz像素时钟、实际370拍水平消隐，加入AXI等待。
- AXI专项覆盖地址/长度保持、4KB边界、帧范围、跨帧排空、缺行整行补黑与错误标志。
- UART到实际读出器：83个Python生成的物理UART请求，逐字节核对应答，包括硬件帧提交、四页回读、CRC及非法参数。
- Python 10项测试通过，包含协议、接口、模拟GUI双向翻转/裁剪/缩放/回读/恢复默认。

```powershell
python -m unittest host.test_host -v
python tools/run_geometry_uart_sim.py
python tools/run_transform_sim.py --width 1280 --height 8
python tools/run_transform_sim.py --width 1280 --height 720 --fullframe
python tools/run_uart_sim.py
python tools/run_sobel_sim.py --width 1280 --height 8
```

ModelSim需在PATH内，或设置 `MODELSIM_BIN`。日志在 `tools/debug/compile-transform.log`、`tools/debug/transform_sim_*/simulation.log`、`tools/debug/uart_geometry_sim/simulation.log`。

**尚未下载真实板卡、连接真实COM口或确认HDMI画面。** 上板顺序建议：默认几何→左右翻转→上下翻转→0.5倍→中心640×360裁剪并放大2倍→恢复默认；用有方向性的物体核对回读及画面。

高斯等固定尺寸滤波仍可串接原RGB/HS/VS/DE流水。后续冻结、回放、对比需要另行设计帧保留/释放、写覆盖策略、帧元数据和多路读带宽；本版未将读帧索引直接暴露为这些命令。
