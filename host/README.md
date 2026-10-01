# VF-Ti60 图像控制台 V0.16

配套 `outflow/Ti60_AR0135_v016_gaussian_scharr_canny.bit`。串口仅传控制和状态；HDMI采集接口已预留，通路尚待接入。

```powershell
python -m pip install -r host/requirements.txt
python -m host.gui
```

也可双击 `host/start_gui.bat`。本机Python为 `D:/python/python.exe`；`python -m host.gui --demo` 为模拟控制演示，不连接板卡。

- 帧冻结：保存当前直播帧到DDR，直播继续，最多8帧。
- 暂停/继续：暂停显示或回到直播，摄像头后台采集继续。
- DDR冻结帧仓库：按编号回放，Ctrl/Shift多选后HDMI对比，显示已存/上限，可清空。
- 本地图片仓库：原有缩略图、编辑、另存、导出、多图对比保留。DDR编号不冒充已下载图片。
- 编辑器：拖动模式或鼠标中键移动，方向键微调，自适应居中、铺满显示框。
- HDMI预览：默认待接入，无串口传图；后续适配器实现 `host/hdmi_source.py` 的 `HDMIFrameSource`。
- 阈值回车、Sobel/中值/反相及单帧几何控制继续保留。默认按钮恢复直播及图像默认设置，保留阈值和已存DDR帧。

DDR记录断电/复位失效；本地PNG永久保存。多帧对比固定展示完整源图并经过当前ISP。详细接口、限制及上板步骤见 [V0.15说明](../docs/DDR_STORE_V015_GUIDE.md)。

测试：`python -m unittest host.test_host host.test_snapshots -v`，`python tools/run_store_sim.py`。

## V0.16 新增图像处理

新增高斯、保边降噪、Scharr、Canny开关。Sobel/Scharr/Canny互斥，Canny自动开启高斯。保边降噪需高斯开启；Canny是两轮邻域连接的流式变体。新功能默认关闭，旧Sobel像素结果保留。阈值仍回车提交，默认按钮同时关闭新增功能。详细算法、时序、限制及验证见 [V0.16说明](../docs/ADVANCED_ISP_V016_GUIDE.md)。

## v1.1 神经网络手势识别

新增“手势识别”窗口，提供启动/停止和中文结果展示，使用UART 0x40/0x41命令，需要包含CNN的新固件。原V0.16 bitstream不支持此功能。启动器现在优先使用项目的 `ml/.venv` Python环境。

开发板未连接时，`host/start_gui.bat --demo` 只检查界面和启停状态，不产生假识别结果。GUI尚未接入HDMI画面；手需放在原始画面中央512×512区域内。结果门限、拒识规则、公开数据准确率和未验证项详见 [v1.1实现说明](../docs/NEURAL_NETWORK_V1_1_IMPLEMENTATION.md)。

## v1.2 全画面定位（开发中）

GUI兼容0x12自动定位协议：通过0x42读取最近裁剪窗口的x、y、边长，在手势窗口显示坐标与全画面模式说明；0x11固件仍显示中央区域提示。启停按钮及五类中文结果沿用原接口。窗口坐标不等于HDMI画面叠框。当前检测模型仍在优化，尚未发布或上板验证v1.2 bitstream，不能用v1.1固件验证全画面检测。见 [v1.2开发记录](../docs/NEURAL_NETWORK_V1_2_DETECTION.md)。
