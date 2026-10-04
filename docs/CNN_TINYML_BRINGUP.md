# CNN TinyML 接入：RAW8 准备接口

本工作分支 `feat/cnn-tinyml-bringup` 来自正式 main `51f7e55f8ce8614f2801f93e5af9bd7bc2c91c01`。所有修改和仿真位于桌面独立副本 `CNN-Tutorial-FPGA`；原 `fpga-w.-codex` 目录不修改。

对应 CNN-Tutorial **阶段 5.2**：为后续手势模型保留传感器 RAW8。现有采集模块将 RAW8 变成 RGB565，最多只能从绿色分量恢复 6 位灰度。因此新增 `ar0135_capture.gray8`，在 `pixel_valid` 有效时输出同一像素的完整 8 位值；顶层接到 `cnn_raw_gray8`，时钟域为 `w_cmos_pclk`。原 RGB565、帧/行有效与 DDR 写入路径不变。

此信号暂未接入消费者，综合可优化掉它。没有 ROI 缩放、输入缓冲、Sapphire 或 TinyML 实例，不能称为已部署模型。后续先运行静态 golden vectors，再设计 DDR 仲裁与输入缩放，最后接实时推理和 HDMI 叠加。

## 已执行验证

在修改前、修改后分别运行：

```powershell
$env:MODELSIM_BIN='D:\WORK\modelsim\win64'
python tools/run_ar0135_sim.py
python tools/check_video_config.py
```

修改后仿真输出：

```text
PASS AR0135: ACK/retry/missing-device/ID/delays/ROI/AE, RAW8+RGB565 aligned,
2 full720p frames (1843200 pixels)
Errors: 0, Warnings: 0
```

每个有效像素都检查新 RAW8 及旧 RGB565，而非只检查输出个数。原初始化/缺失摄像头/I2C重试/运行时曝光回归保留。720p 传感器、时钟、DDR、显示及外围一致性检查通过。本轮没有做完整 FPGA 综合、时序或上板验证，没有生成可宣称通过的新 bitstream。

## 需要继续核对

- `Ti60_AR0135.xml` 配置 Ti60F225 C4、Efinity 2026.1.132.3.9；现有工程未实例化 Sapphire/TinyML。
- DDR 已保留 12×4 MiB 帧槽，不可将推理 arena 与其重叠；新增 master 需仲裁、缓存一致性与帧所有权设计。
- 训练输入为 64×64 单通道、Pillow bilinear，现有几何最近邻不能无验证替换。
- 参照厂商 DDR3 TinyML 示例时核对 IP/BSP/速度等级；官方 DevKit 外围配置不直接覆盖本工程。

模型与教学记录位于 [CNN-Tutorial](https://github.com/Starfall-git/CNN-Tutorial)，INT8 模型 SHA-256 为 `7891518a9b70ec6b3be8649123651780ce87ede1e69a9a49c394c17d203a0baa`。固件模型数据包由该项目 `scripts/export_board_bundle.py` 生成，保留在本地 artifacts。
