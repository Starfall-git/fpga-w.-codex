# CNN TinyML 接入：RAW8 接口与静态固件

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

## 阶段 5.3：RISC-V 静态固件交叉编译

新增 `firmware/cnn_static/main.cc` 与 `tools/build_cnn_static.py`。用户提供的 SDK 在 `Work/FPGA Contest/env/RISCV-IDE`，GCC/G++ 实测 13.4.0。使用本地 DDR3 示例 BSP/启动文件，配合官方 TinyML 2026.1.132 固定提交 96886fa0c73e25e6218db7d0863f84677cf65138 的完整 runtime。依赖复制到 ignored artifacts 后编译，参考文件不改写。

应用初始化 BSP UART，检查模型与张量契约，注册五类算子，装入三组 golden 输入，输出逐字节差、argmax、arena 和 64 位周期。仅三组字节全部一致时打印 PASS。默认不调用硬件探测 `init_accel()`，厂商加速设置保持零初始化；尚未验证目标执行。main 只支持 hart 0。

2026-10-04：108 个翻译单元编译链接通过。结果在 `artifacts/cnn-static-2026-r5/`，ELF SHA-256 为 `3d65ae1f03ec620c9cab6afa06ca81399e36242dd5bbd3fd930ae49d666ca0d4`，RV32IM/ilp32，入口 0x1000。text 92,992 B、data 58,686 B、GNU size 的 bss 总计 2,359,928 B（含默认 2 MiB 栈）。实际 .bss 262,776 B，其中 256 KiB arena 仅测试容量上限，实际使用量待运行测量。

保留 newlib nosys 未实现 POSIX 调用和 RWX LOAD 警告；没有宣称零警告。应用 UART 使用 BSP，仍需板端核实 runtime 其他路径。默认 linker 从 0x1000 开始并与现有低 48 MiB 视频帧槽冲突，不能把当前 ELF 直接装进视频系统。

构建示例：

```powershell
python tools/build_cnn_static.py --vendor-workspace '<旧 DDR3 示例 embedded_sw/sapphire_soc_tinyml>' --runtime-workspace '<固定官方 2026 示例 embedded_sw/SapphireSoc>' --sdk '<RISCV-IDE>' --bundle '<CNN-Tutorial/artifacts/v0.3-board-bundle>' --output artifacts/cnn-static-new
```

脚本拒绝覆盖既有输出，并核对数据包每个文件哈希。生成源码哈希清单、compile/link 日志、ELF 属性及 JSON 报告。SDK/厂商源码、模型及编译产物不提交 Git。完整路径和教学 Notebook 05 在 [CNN-Tutorial 静态固件文档](https://github.com/Starfall-git/CNN-Tutorial/blob/feat/v0.4-fpga-static/docs/04_deployment/riscv_static_firmware.md)。

## 用户指定文档的接入结论

已核对《RISCV Custom Instruction》第 3–6 页、《Sapphire v6.1》第 13–14、25 页以及《TinyML 框架介绍》第 2–9 页。CI 为 10-bit function ID、两个 32-bit 输入和一个 32-bit 输出，命令/响应分别握手。实例连接必须与厂商 runtime 的 ID 定义匹配。DMA 与 CPU cache 不自动一致，后续需要完成同步、invalidate、缓冲所有权和 frame_id；只加 volatile 无法替代。

下一步先建立匹配本板 C4/DDR3/引脚/时钟的独立 Sapphire 硬件，取得静态 golden 日志，随后才启用匹配的 TinyML 加速器。当前未生成新视频 bitstream、未下载设备、未测 FPS；该 Draft PR 保持阶段 5 接入过程状态。
