# VF-Ti60 图像控制台 V0.14

2026-09-28。配套 `outflow/Ti60_AR0135_v014_snapshot_gallery.bit`，新增DDR冻结帧、图片仓库、编辑和多图对比。

在工程根目录运行：

```powershell
python -m pip install -r host/requirements.txt
python -m host.gui
```

也可双击 `host/start_gui.bat`。本机解释器为 `D:/python/python.exe`；无硬件演示用 `python -m host.gui --demo` 后点击连接。

- 默认显示原图；“中值滤波”和“Sobel边缘检测”可独立点击切换，支持四种组合；“黑白反转”只作用于 Sobel。
- 阈值0～4095，输入后回车。当前恢复版灰度强度输出按UART阈值扣除后缩放；保留V0.13弱轮廓表现。
- 上下/左右翻转点击即提交。
- 缩放保留预置，也可输入10%～500%后回车，支持两位小数。
- 裁剪输入源图X/Y/宽/高，回车或点击“裁剪”。
- “默认”恢复全图、100%、不翻转、中值滤波关闭、Sobel关闭、正常黑白，保留阈值。
- 连接旧 bit 时中值滤波按钮自动禁用；设备必须在状态能力位 bit7 声明支持。
- “设备已确认”显示硬件回读；忙碌时保留同类操作的最新值。通信记录默认折叠。

串口仍为115200/8N1。RX F10、TX E10是FPGA封装管脚，配置电平1.8V；接线按实际板卡电路核对。HDMI输出继续保留；冻结帧通过串口逐行下载，115200下整帧约4～5分钟。

八方向算法与调试方法见 [V0.11 算法说明](../docs/SOBEL8_GRAY_V011_GUIDE.md)。摄像头方向与白线修复见 [V0.10 修复说明](../docs/ORIENTATION_BORDER_V010_GUIDE.md)；中值滤波接口见 [V0.9 中值滤波说明](../docs/MEDIAN_V09_GUIDE.md)。

测试：`python -m unittest host.test_host -v`。本版已完成软件/RTL仿真与Efinity编译，实际显示仍需下载到板卡确认。冻结帧仓库、编辑及多帧静态对比已加入；连续视频回放不在本版范围。

操作：冻结当前帧并入库 → 冻结帧合集 → 点击缩略图编辑，或勾选多图对比；恢复实时后抓取下一帧。详见 [V0.14 使用与接口说明](../docs/SNAPSHOT_GALLERY_V014_GUIDE.md)。

新增回归：`python -m unittest host.test_snapshots -v`。
