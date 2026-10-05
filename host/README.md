# VF-Ti60 图像控制台 V0.21

## TinyML 集成调试版（2026-10-05）

独立副本新增 **图像 → TinyML 手势** 按钮，在“曝光 / 算法调节”旁边。
关闭旧窗口后重新运行 `host/start_gui.bat` 才会加载更新。新面板提供独立的
“启用推理”“叠加识别结果”“应用设置”“读取实际状态”，显示请求值和实际回读。
旧 bit 未声明 CNN 能力时禁用控制；静态自检 ELF 不声明实时推理就绪，面板会显示
“推理固件未就绪”，此时不能启用推理。叠加开关也不会生成不存在的识别结果。
模拟演示明确标注模拟，不代表板上运行结果。

连接失败现在区分“COM 口无法打开”和“COM 已打开但 FPGA 协议握手超时”。
后者无需先运行 RISC-V ELF 才能解决：原控制 UART 由 FPGA 逻辑直接处理。
若 Programmer 刚使用 `SPI Active using JTAG Bridge`，须等待 Flash 操作完成，
再确认业务设计已重新配置。首次调试请选择 **JTAG + 本候选的 `.bit`**，不能把
Flash 编程桥成功加载当作业务电路已运行。UART 为 USB-UART（目前枚举 COM8）
115200/8N1；FT232H JTAG 下载器与这个 COM 口是不同设备。

对应候选工程：`artifacts/evsoc-system-r1/Ti60_AR0135.xml`。
下面 V0.21 及更早版本说明继续适用于原视频功能；其中旧 bit 文件不用于 TinyML 调试。

配套 `outflow/Ti60_AR0135_v020_auto_exposure_fix.bit`。串口仅传控制和状态；HDMI实时预览已接入USB采集卡。

```powershell
python -m pip install -r host/requirements.txt
python -m host.gui
```

也可双击 `host/start_gui.bat`。本机Python为 `D:/python/python.exe`；`python -m host.gui --demo` 为模拟控制演示，不连接板卡。

- 记录帧：保存当前直播帧到DDR，直播继续，最多8帧。
- 帧冻结/实时显示：冻结显示或回到直播，摄像头后台采集继续。
- DDR冻结帧仓库：按记录顺序排列，可修改唯一编号、读取HDMI缩略图、选中后×删除、多选对比；关闭自动恢复实时。
- 本地图片仓库：原有缩略图、编辑、另存、导出、多图对比保留。DDR编号不冒充已下载图片。
- 编辑器：右键拖动，裁剪后返回画笔；下拉选择图形/文字/橡皮，支持撤销、复原和覆盖保存。
- HDMI预览：选择USB采集卡（本机Hagibis），开始预览；支持保存到仓库及另存为任意本地目录，图像保持采集原分辨率。
- 阈值回车、Sobel/中值/反相及单帧几何控制继续保留。默认按钮恢复直播及图像默认设置，保留阈值和已存DDR帧。

DDR记录断电/复位失效；本地PNG永久保存。多帧对比固定展示完整源图并经过当前ISP。详细接口、限制及上板步骤见 [V0.15说明](../docs/DDR_STORE_V015_GUIDE.md)。

测试：`python -m unittest host.test_host host.test_snapshots -v`，`python tools/run_store_sim.py`。

## V0.16 新增图像处理

新增高斯、保边降噪、Scharr、Canny开关。Sobel/Scharr/Canny互斥，Canny自动开启高斯。保边降噪需高斯开启；Canny是两轮邻域连接的流式变体。新功能默认关闭，旧Sobel像素结果保留。阈值仍回车提交，默认按钮同时关闭新增功能。详细算法、时序、限制及验证见 [V0.16说明](../docs/ADVANCED_ISP_V016_GUIDE.md)。

USB采集卡接线、使用和验证见 [V0.17说明](../docs/HDMI_CAPTURE_V017_GUIDE.md)。V0.17只修改上位机；当前V0.18必须更新比特流。

当前交互、协议与5帧以上闪烁修复见 [V0.18说明](../docs/GALLERY_COMPARE_V018_GUIDE.md)。


## V0.19 曝光与算法调节

V0.19 的曝光流程已由 V0.20 修复：手动调整后恢复持续自动调光，“自动调光”恢复上电配置及自动曝光、模拟/数字增益。点击滑块后支持左右键微调。手动值可能被自动算法重新调整。故障原因、增益解释及验证见 [V0.20说明](../docs/AUTO_EXPOSURE_V020_FIX.md)。

新增可选双级高斯、Scharr近似L2幅度、Canny六轮弱边连接、孤立候选抑制，以及25%～75%低阈值比例。“尝试降噪与连续轮廓组合”启用前三项，原有高斯/边缘算法开关仍在主界面；新选项默认关闭。Sobel原有算术不变。

“默认”在硬件端恢复摄像头及算法配置，并继续保留阈值和DDR仓库。V0.19需配套新bit和新GUI；旧bit仍可控制原功能，但曝光调节入口禁用。算法差异、寄存器、仿真结果、限制及调节步骤见 [V0.19说明](../docs/EXPOSURE_ISP_V019_GUIDE.md)。

## V0.21 手动 / 自动调光

新增“手动调光”按钮，保持当前滑块值并关闭持续自动调整；滑块修改保持当前模式。“自动调光”重新启动自动调整并持续适应环境。沿用V0.20比特流。操作说明见 [V0.21说明](../docs/MANUAL_AUTO_V021_GUIDE.md)。此模式规则取代V0.20所有调参均恢复自动的行为。
