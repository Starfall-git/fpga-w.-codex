# VF-Ti60 图像控制台 V0.5

2026-09-22。已实现 FPGA 实时控制：Sobel阈值、上下/左右翻转、自定义裁剪、最近邻放大/缩小。配置在帧边界应用，上位机收到确认后查询硬件实际配置。

在工程根目录运行（Python 3.10+、Tkinter）：

```powershell
python -m pip install -r host/requirements.txt
python -m host.gui
```

也可双击 `host/start_gui.bat`。本机测试解释器为 `D:/python/python.exe`。无硬件演示使用 `python -m host.gui --demo`，进入后点击“连接”。模拟模式不会打开COM口，也不会显示真实摄像头图像。

下载 `outflow/Ti60_Demo_transform_720p.bit`，选择正确COM口，默认 **115200、8N1、无流控**。RX F10、TX E10为FPGA封装管脚，工程电平 **1.8V**；请按实际板卡串口电路连接。

GUI输入或勾选后点击对应“应用到FPGA”。阈值范围0～4095；裁剪坐标相对原始1280×720帧；先裁剪，再翻转和缩放，输出保持720p，居中补黑或中心截取。默认Sobel继续作用于变换后的图像。

“恢复全图 / 1倍 / 不翻转”依次提交三个操作；“保存配置草稿”和“预览命令”不会写入硬件。显示的已确认配置与输入草稿分开。旧V0.4设备仍可调阈值，几何按钮会根据能力位禁用。

完整资料见 [几何控制与DDR接口说明](../docs/GEOMETRY_CONTROL_GUIDE.md)：修改清单、顶层连接、行缓存结构、跨域与帧边界、UART帧格式、Python API、测试结果和上板步骤。

| 文件 | 职责 |
|---|---|
| `gui.py` | Tkinter界面，后台线程通信 |
| `client.py` | 串口请求/应答、硬件配置核对、模拟客户端 |
| `protocol.py` | CRC8、固定13字节帧、参数校验、配置解析 |
| `test_host.py` | 协议、接口与GUI功能回归 |

```python
from host.client import SerialClient

board = SerialClient('COM5')
try:
    board.get_status()
    board.set_threshold(256)
    board.set_flip(True, False)        # 上下开、左右关
    board.set_crop(320, 180, 640, 360)
    board.set_zoom(2, 1)
    print(board.get_geometry())
finally:
    board.close()
```

运行测试：`python -m unittest host.test_host -v`。本版已完成RTL仿真和Efinity全流程编译，尚未真实串口上板验证。帧冻结、帧回放和帧对比留待后续设计。
