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
