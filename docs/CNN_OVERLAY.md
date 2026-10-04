# CNN 结果邮箱与视频 Overlay

阶段 5 的待集成模块，尚未写入 example_top.v、Efinity 项目或下载板卡。

`src/cnn/cnn_overlay_bridge.v` 将 CPU 结果域接到像素域：`cnn_result_mailbox.v` 用一个稳定数据槽及请求/应答翻转握手，`cnn_video_overlay.v` 在现有 ISP 后叠加 ROI 边框和 P/R/S 字符。数据顺序是 frame_id(32)、valid(1)、class(2)、x0/y0/x1/y1(各12)，合计 83 位，右/下边界为开区间。

- 生产者只在 result_ready=1 时提交；忙时不得覆盖已接收结果。没有视频 ready 信号，AI 侧等待不会反压像素流。
- mailbox 只在 VS 进入有效低电平时提交。Overlay 在随后的消隐周期更新坐标；RGB/HS/VS/DE 固定统一延迟一拍。
- `pixel_overlay_enable` 必须已在像素域，不可直连 CPU/UART 多时钟信号。关闭叠加保持完整像素流。全局复位以外的 AI 复位只清空邮箱，已有画面元数据按帧龄过期。
- 默认 30 帧没有新结果则隐藏。该帧数不是推理 FPS，也不以帧号差值代替时间。
- class=0/1/2 为 paper/rock/scissors，显示青/黄/洋红 P/R/S。当前框是固定 ROI，不是检测框。
- 当前坐标必须是显示像素坐标。视频翻转、裁剪、缩放启用时，生产者/桥接层还需要正确映射原相机 ROI；不能直接沿用相机坐标。

运行 `python tools/run_cnn_overlay_sim.py`，默认使用 `D:/WORK/modelsim/win64`。测试时源时钟周期14 ns，像素周期10 ns；9帧16×12逐像素检查，包含独立邮箱及组合桥检查、忙时错误提交、源/目标复位恢复、活动区提交拒绝、帧边界开关、过期、越界ROI、三种字符/颜色。结果为 PASS，零编译/仿真错误和警告。

这是 RTL 数字仿真，不证明物理 CDC 或完整720p链路通过。综合接入后必须针对首级同步寄存器和 bundled-data 路径做 CDC/时序约束与审查，保持数据到目的寄存器的最大延迟满足请求同步提供的稳定时间；禁止用整组时钟 false-path 隐藏数据路径要求。还需720p视频回归、CPU/DDR压力和板上实测。
