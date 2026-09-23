# VF-Ti60 图像控制台 V0.6

2026-09-23。请配套下载 `outflow/Ti60_Demo_v06_controls_720p.bit`。

在工程根目录运行：

```powershell
python -m pip install -r host/requirements.txt
python -m host.gui
```

也可双击 `host/start_gui.bat`。本机解释器为 `D:/python/python.exe`；无硬件演示用 `python -m host.gui --demo` 后点击连接。

- 默认显示原图；“Sobel边缘检测”和“黑白反转”点击切换。
- 阈值0～4095，输入后回车，不再点击确认或查询。
- 上下/左右翻转点击即提交。
- 缩放保留预置，也可输入10%～500%后回车，支持两位小数。
- 裁剪输入源图X/Y/宽/高，回车或点击“裁剪”。
- “默认”恢复全图、100%、不翻转、Sobel关闭、正常黑白，保留阈值。
- “设备已确认”显示硬件回读；忙碌时保留同类操作的最新值。通信记录默认折叠。

串口仍为115200/8N1。RX F10、TX E10是FPGA封装管脚，配置电平1.8V；接线按实际板卡电路核对。串口只传控制，图像仍通过HDMI输出。

完整修改清单、延迟分析、RTL接口、串口增量、默认扩展规范和测试说明见 [V0.6操作与接口说明](../docs/GUI_V06_GUIDE.md)。几何读出架构参考 [V0.5架构说明](../docs/GEOMETRY_CONTROL_GUIDE.md)。

测试：`python -m unittest host.test_host -v`。本版已完成软件/RTL仿真与Efinity编译，尚未真实上板测量延迟。帧冻结、回放和对比尚未加入。
