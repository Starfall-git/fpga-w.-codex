# VF-Ti60 图像控制台 V0.10

2026-09-24。建议配套下载已修正摄像头方向和图像边缘的 `outflow/Ti60_AR0135_v010_orientation_border.bit`。

在工程根目录运行：

```powershell
python -m pip install -r host/requirements.txt
python -m host.gui
```

也可双击 `host/start_gui.bat`。本机解释器为 `D:/python/python.exe`；无硬件演示用 `python -m host.gui --demo` 后点击连接。

- 默认显示原图；“中值滤波”和“Sobel边缘检测”可独立点击切换，支持四种组合；“黑白反转”只作用于 Sobel。
- 阈值0～4095，输入后回车，不再点击确认或查询。
- 上下/左右翻转点击即提交。
- 缩放保留预置，也可输入10%～500%后回车，支持两位小数。
- 裁剪输入源图X/Y/宽/高，回车或点击“裁剪”。
- “默认”恢复全图、100%、不翻转、中值滤波关闭、Sobel关闭、正常黑白，保留阈值。
- 连接旧 bit 时中值滤波按钮自动禁用；设备必须在状态能力位 bit7 声明支持。
- “设备已确认”显示硬件回读；忙碌时保留同类操作的最新值。通信记录默认折叠。

串口仍为115200/8N1。RX F10、TX E10是FPGA封装管脚，配置电平1.8V；接线按实际板卡电路核对。串口只传控制，图像仍通过HDMI输出。

摄像头方向与白线修复见 [V0.10 修复说明](../docs/ORIENTATION_BORDER_V010_GUIDE.md)；中值滤波接口见 [V0.9 中值滤波说明](../docs/MEDIAN_V09_GUIDE.md)。

测试：`python -m unittest host.test_host -v`。本版已完成软件/RTL仿真与Efinity编译，实际显示仍需下载到板卡确认。帧冻结、回放和对比尚未加入。
