# r5：AR0135 动态采集、手势推理与叠加调试

阶段 6 子步骤：将已通过 r4 静态测试的模型接到实际摄像头。此版本仍是上板调试版；完整阶段 6 的视觉效果、真实手势准确率和稳定性需要用户验收。

## 打开与下载

- Efinity 工程：`C:/Users/SteLl1a/Desktop/CNN-Tutorial-FPGA/artifacts/evsoc-live-r5/Ti60_AR0135.xml`。
- 匹配比特流：同目录 `outflow/Ti60_AR0135.bit`，或发布包 `hardware/Ti60_AR0135.bit`。
- 使用 Programmer **JTAG** 模式下载 `.bit`。随后释放 Programmer 的下载操作，运行本包 `start-openocd.ps1`，在另一 PowerShell 窗口运行 `start-gdb.ps1`。
- `start-gdb.ps1` 加载匹配 ELF、回读五个段、启动程序并检查 `CNN_LIVE`，成功后 CPU 保持运行。
- RISC-V 应用源码：`artifacts/evsoc-system-r1/embedded_sw/SapphireSoc/software/standalone/evsoc_tinyml_gesture_live`；产物名仍为 `evsoc_tinyml_gesture.elf`。原始静态应用保留。

不要将 r4 硬件与 r5 动态 ELF 混用：r5 新增了摄像头快照 APB 接口。所有操作均为易失 JTAG 调试，不写 Flash。断电或重新配置 FPGA 后需要重新加载 ELF。

## 上位机与画面

运行 `C:/Users/SteLl1a/Desktop/CNN-Tutorial-FPGA/host/start_gui.bat`，连接 COM8、115200，打开“图像 → TinyML 手势”。固件完成模型和第一幅摄像头快照初始化后，推理才变为可用。分别打开“推理”和“叠加”。

首次测试保持 1280×720、缩放 100%、不裁剪。将手放在画面中央 512×512 区域：坐标 `[384,104)–[896,616)`，准确写法为左上 `(384,104)`、右下排他 `(896,616)`。彩色框表示**固定分类区域**，并非检测器找到的物体框。P=布（青色）、R=石头（黄色）、S=剪刀（品红色）。原 Sobel 等处理可独立切换；模型读取其处理前的 RAW8 灰度数据。

模型只有三类，未训练“无手”类；背景也会被分到某一手势。实拍准确率需要后续域适配。当前叠加坐标尚未跟随缩放/裁剪变换；不能用本次测试宣称任意几何变换已验证。

## 两条链路与关键实现

原相机 → DDR3 → 图像处理 → HDMI 通路保持原有功能。新增通路仅旁路读取 `ar0135_capture.gray8/frame_valid/pixel_valid`，不会对相机或原视频施加反压。

`cnn_gray_snapshot.v` 在中心 ROI 内以 8 像素间隔取样，得到 64×64 RAW8。每四个像素打包为一个 32 位字，使用 4 个双时钟 RAM 块。CPU 请求跨域后等待下一帧；完整采集结束才开放读窗口，读取期间缓存冻结。CPU 全部读完才请求下一帧，可与当前 Invoke 重叠。截断帧和复位后的旧数据不会作为有效输入。

当前缩小采用最近邻中心采样，未加入抗混叠滤波，和训练图像的一般双线性缩放并不完全相同。这是低资源动态链路验证版本；实拍数据与预处理一致性属于后续准确率优化。

`live_main.inc` 保留官方 EVSoC 派生应用的 `tinyml_init`、中断初始化与 TinyML Accelerator 调用，通过 `pixel - 128` 将 RAW8 转为当前模型的 INT8 输入。主循环检查 UART 推理开关、采集、Invoke、argmax，再通过既有 APB 邮箱提交分类区域。关闭推理后不再启动新的 Invoke，正在执行的一次可以完成。

## APB 扩展

基址来自生成 BSP 的 `IO_APB_SLAVE_1_INPUT = 0xf8100000`。原结果寄存器 `0x00–0x28` 保持兼容。

| 偏移 | 含义 |
|---|---|
| `0x40` | 只读 `CAP1` 签名 `0x43415031` |
| `0x44` | bit0 ready、bit1 busy、bit2 capture error |
| `0x48` | 写 1 请求下一完整帧；busy 时拒绝 |
| `0x4c` | 当前快照相机帧号 |
| `0x50/0x54` | ROI 左上/右下排他坐标 |
| `0x58` | 有效像素数，成功为 4096 |
| `0x1000–0x1ffc` | 1024 个只读 32 位字，每字四个 RAW8，低字节在前 |

## 验证与限制

- ModelSim：4,118 次 APB 检查通过，覆盖四幅完整图像、缓存冻结、截断帧、帧中请求、CPU 单独复位。既有 UART/视频隔离测试在原端点和新封装均通过。
- 官方 Efinity map/interface/pnr/pgm 全部通过。59,185/60,800 XLR，244/256 RAM，57 DSP；96 MHz setup 裕量 +0.322 ns。两条既有 JTAG 跨域 setup 为 -0.293/-1.297 ns，尚未完成时序签核。
- 实际摄像头第一幅保留输入：校验和与固件读入值一致；板端与 TensorFlow 2.15.1 `BUILTIN_REF` 输出均为 `[5,70,-92]`。
- 已观测连续 431 次推理/提交，无采集错误、无发布拥堵；该时刻循环约 72.9 ms（约 13.7 次/秒），Invoke 约 70.6 ms。不是已达到端到端 15 FPS，也不是长时间稳定性结论。
- JTAG 检查会暂停 CPU，因此其间隔不能用于统计持续 FPS。`cnn_live_status.pause_after_completed` 仅用于调试取样；正常运行设为 0。TFLM 会复用输入内存，因此核对采用 Invoke 前专用输入副本，并验证校验和，不能直接读取 Invoke 后的原输入张量冒充原始输入。
- HDMI 实际可见框、类别随手势变化、长时间运行和几何变换仍需用户确认。寄存器的“已提交”不等于 HDMI 视觉验收完成。

原始 `C:/Users/SteLl1a/Desktop/fpga-w.-codex` 未修改。r4 的工程、固件和发布包保持可回退。
