# V0.6：快捷交互、低延迟串口与运行时图像模式

2026-09-23。请配套下载 `outflow/Ti60_Demo_v06_controls_720p.bit`，再运行新版GUI。仅升级Python不能让旧RTL支持新模式和10%～500%倍率。

## 1. 操作变化

在工程根目录运行 `python -m host.gui`，或双击 `host/start_gui.bat`。本机解释器为 `D:/python/python.exe`。默认串口仍为115200/8N1；引脚、电平和HDMI分辨率未改动。

| 控件 | 新操作 |
|---|---|
| 阈值 | 输入0～4095，按回车提交；删除确认和查询按钮，自动回读硬件值 |
| 上下/左右翻转 | 点击复选框即发送，再点关闭，无需“应用到FPGA” |
| 缩放 | 保留10%、25%、50%、100%、150%、200%、300%、400%、500%预置；选中即发送 |
| 自定义缩放 | 在同一输入框输入10%～500%，回车应用；可省略百分号，最多两位小数，例如123.45% |
| 裁剪 | 编辑X、Y、宽、高，任一输入框回车，或点击“裁剪” |
| Sobel边缘检测 | 默认关闭，输出原始彩色图；点击开启，再点关闭 |
| 黑白反转 | 默认关闭；Sobel开启时，白边黑底与黑边白底互换 |
| 默认 | 恢复全图、100%、不翻转、Sobel关闭、黑白反转关闭，**保留Sobel阈值** |

黑白反转不反相原始RGB图像。在原图模式下可以先设反相状态，之后开启Sobel时生效。无完整3×3窗口的边界，在反相模式下变白；消隐区域始终为0，HS/VS/DE不被反相。

缩放继续采用最近邻，居中补黑或居中截取，不自动拉伸裁剪区域。裁剪和倍率组合若导致输出宽或高不足1像素，硬件拒绝该操作并保留旧值。参数框表示输入目标，“设备已确认”显示真实回读值。

“通信记录”默认折叠。界面删除了协议预览、草稿保存、手动查询等干扰日常调节的按钮，底层协议和Python API仍可用于调试。模拟模式不会打开串口，也不代表真实板卡已应用。

## 2. 延迟原因与修复

检查本机pyserial的Windows `Serial.read()`实现及旧客户端代码，确认旧 `read(128)`请求128字节，而响应仅13字节，设置的50ms读取超时通常成为每包的额外等待。旧GUI还每次轮询“状态+4页几何配置”，可累计约250ms；完成结果由50ms定时器接收。忙碌期间用户操作直接返回，也会造成“按了没反应”的体验。

本版修改：

1. 串口无数据时只等待首字节，之后读取 `in_waiting` 中已有字节；完整应答到达立即返回，仍校验序号、CMD和CRC。保留1秒命令超时，不用无条件重发掩盖故障。
2. GUI完成事件检查由50ms改为5ms。
3. 定时轮询只查询一包状态，回读按键阈值和图像模式；几何四页仅在连接或几何操作后读取。
4. 正在通信时仍接受交互请求；同一类未发送请求合并为最后一个值，收到当前应答后立即执行。不会因轮询忙碌丢弃回车/点击。
5. “默认”取消尚未发送的几何和模式修改，但保留尚未发送的最新阈值请求；在途命令正常结束后再恢复默认。

真实串口模式下显示“最近命令往返xx ms”，计时从写入请求到收到匹配应答，**不含GUI排队、HDMI扫描和显示器延迟**。当前没有真实COM口测量，因此不宣称上板总延迟已降到某个数值。阈值/模式仍要等待帧消隐，正常运行时最多约一帧等待；USB串口驱动、显示器和DDR异常也会影响最终观感。

## 3. RTL改动及接口

顶层追加V0.6编号 **25～29**；修改前备份在 `tools/debug/before-v06/`。源码使用块注释标明变化。

| 文件 | 改动 |
|---|---|
| `example_top.v` | 删除原ENABLE_SOBEL/SOBEL_BINARY参数，连接UART控制器的像素域模式输出 |
| `src/isp/video_processing.v` | ENABLE_SOBEL、BINARY_OUTPUT改为输入端口；始终运行Sobel；原图旁路也延迟六拍 |
| `src/isp/video_sobel.v` | BINARY_OUTPUT改为运行时极性输入；1为白边黑底、0为黑边白底 |
| `src/control/threshold_cdc.v` | 邮箱位宽/复位值参数化，复用于两位模式配置；阈值实例维持12位和复位128 |
| `src/control/uart_image_control.v` | 模式设置、统一默认命令、实际模式回读；扩展缩放校验至0.1～5倍 |
| `host/protocol.py` | 百分比精确编码、能力位及模式状态解析 |
| `host/client.py` | 低延迟读取、往返计时、模式/默认API、旧版能力检查 |
| `host/gui.py` | 新交互、合并队列、自动回读、折叠通信记录 |

接口示例：

```verilog
wire ENABLE_SOBEL, BINARY_OUTPUT;
// u_image_control输出，已在clk_pixel域：
// .enable_sobel_o(ENABLE_SOBEL), .binary_output_o(BINARY_OUTPUT)
video_processing #(.IMAGE_WIDTH(1280), .VS_ACTIVE(1'b0)) u_video_processing (
    .clk(clk_pixel), .rst_n(rstn_pixel),
    .ENABLE_SOBEL(ENABLE_SOBEL), .BINARY_OUTPUT(BINARY_OUTPUT),
    .SOBEL_THRESHOLD(SOBEL_THRESHOLD),
    // RGB / HS / VS / DE端口沿用原连接
    ...
);
```

复位值：`ENABLE_SOBEL=0`、`BINARY_OUTPUT=1`、阈值128。Sobel与原图共享同一套六拍延迟后的同步信号，避免从六拍Sobel切换到旧版零拍旁路时跳变显示同步。模式通过稳定邮箱和请求/确认握手，在场消隐提交后才应答。

旧版 `BINARY_OUTPUT=0` 曾表示灰度强度模式；本版按用户需求改为反相。灰度诊断功能另用 `GRAYSCALE_OUTPUT=1` 编译参数保留，默认0且GUI不暴露该诊断选项。

## 4. 协议与默认扩展约定

保留13字节帧和CRC8，不改变波特率。新增：

| CMD | 载荷 | 作用 |
|---|---|---|
| 11 | D0 bit0=Sobel使能、bit1=黑白反相，其余为0 | 同时设置两位模式，并等待像素域确认 |
| 12 | 8字节全0 | 恢复所有已注册功能默认，保留阈值；等待几何和模式都完成后应答 |

标准响应载荷现在是 `[status,threshold_low,threshold_high,version=1,capabilities,isp_flags,0,0]`。`isp_flags` 是实际应用值，不是待提交值。新增能力bit4模式控制、bit5宽倍率、bit6默认命令，完整工程返回7F。

22缩放命令仍为uint16分子/分母，现允许非零uint16值且满足 `0.1 <= 分子/分母 <= 5`。GUI百分比使用精确十进制转分数，例如123.45%=2469/2000，不通过二进制浮点舍入。所有乘积/范围比较先扩展到32位。

“默认”统一在RTL的12命令处理分支维护，GUI只发送这一条语义命令，不罗列功能。**后续新增功能时必须把其默认值和完成条件登记到该分支，并补充回读/回归测试**，这样GUI按钮无需再增加逐项重置逻辑。未知的未来功能不会凭空自动复位。

几何与模式各自在其安全帧边界提交；两者全部完成后才返回默认成功，不保证它们在同一时钟拍切换。默认命令不清除历史诊断标志，也不修改阈值、串口、连接或板上运行状态。

新GUI可继续控制旧bitstream已有的功能，但会禁用新模式/默认控件，宽倍率也会被能力检查拦截。本次应配套使用V0.6 GUI和bitstream。

```python
from host.client import SerialClient
from host.protocol import percent_ratio
board = SerialClient('COM5')
try:
    board.get_status()
    board.set_threshold(256)
    board.set_isp(True, True)       # Sobel开启、黑白反相
    board.set_zoom(*percent_ratio('123.45%'))
    status, geometry = board.reset_defaults()  # 阈值仍为256
finally:
    board.close()
```

## 5. 验证

- Efinity综合、接口、布局布线及bitstream导出通过。最终报告列出的setup/hold均为正；系统域setup 3.642ns、像素域8.673ns。
- 113个Python生成的物理UART请求通过RTL：包含模式翻转、非法模式、10%/500%/小数比例、设备默认、实际像素域模式端口和阈值保留。
- Sobel逐拍参考测试通过：正常/反相、边界颜色、灰度、六拍原图旁路、动态使能、HS/VS/DE对齐。
- Python 13项测试通过：输入校验、默认保阈值、真实回读解析、串口不等待凑齐128字节、忙碌合并请求、GUI点击与回车绑定。
- 扩展720p几何仿真通过12组整帧配置、11,059,200像素检查，覆盖10%～500%及小数比例；日志见 `tools/debug/transform_sim_1280x720/simulation.log`。

复现：`python -m unittest host.test_host -v`、`python tools/run_geometry_uart_sim.py`、`python tools/run_sobel_sim.py --width 1280 --height 8`、`python tools/run_transform_sim.py --width 1280 --height 720 --fullframe`。编译日志：`tools/debug/compile-v06.log`。

尚未替用户下载板卡或进行真实串口/HDMI联调。建议上板先确认默认原图，再开启Sobel、切换反相、调阈值回车、试10%与500%，最后点击“默认”并确认阈值保留。
