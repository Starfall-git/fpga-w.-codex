# Sapphire 手势结果 APB 接口

阶段 6 子步骤：在官方 EVSoC 的 APB 控制形式上增加手势结果提交接口。官方 `edge_vision_soc.v` 的 `io_apbSlave_1_*` 连接 `common_apb3`，软件使用 `src/platform/vision/apb3_cam.h` 中的 MMIO 读写函数。本实现沿用 APB 信号及官方 `io.h`，为三类手势定义独立 ABI，不复用原 YOLO/摄像头寄存器的语义。

## 寄存器布局

模块 `src/cnn/cnn_result_apb.v` 使用 16 位局部字节地址。总线32位、字对齐，无字节写使能。所有传输零等待。全地址解码，未定义或非对齐地址、只读寄存器写入均返回 PSLVERROR。

| 偏移 | 访问 | 含义 |
| --- | --- | --- |
| 0x00 | R | 0x47535431，GST1 ABI标识 |
| 0x04 | R | bit0 mailbox ready；bit1 上次提交被拒绝的粘滞标志 |
| 0x08 | RW | 相机来源帧号32位 |
| 0x0c | RW | ROI x0[11:0]，y0[27:16]，其余位清零 |
| 0x10 | RW | ROI x1[11:0]，y1[27:16]，其余位清零 |
| 0x14 | W/R0 | 写入严格等于1时提交完整结果；读0 |
| 0x18 | RW | bit0 valid；bit[2:1] class：0纸、1石头、2剪刀 |
| 0x1c | R | 接收次数，32位自然回卷；不是显示次数 |
| 0x20 | W/R0 | 写bit0=1清除拒绝标志；读0 |
| 0x24 | R | bit0 CPU域允许启动新推理；bit1 AI在线 |

软件先读 ready，再写帧号、坐标、类别，最后 fence 后写 commit。仅 hart0 一个生产者可使用此接口；多线程/中断调用需自行串行化。复位过程中不得发布，复位后重新读 ABI/ready。返回1表示入队，0表示忙，-1表示参数错误。未配置真实基址，因此 `firmware/evsoc_gesture/gesture_result.h` 要求调用者传入最终 BSP/地址解码器确认的基址。

提交时邮箱锁存整个83位数据包。提交后软件可准备下一帧影子寄存器，不影响未显示的数据。忙时 commit 返回 PSLVERROR 并置拒绝标志，既不覆盖前一帧，也不等待视频端；直接绕过 ready 检查的错误软件需要总线异常处理。valid=0也可提交，用于在帧边界清除结果。类别、显示宽高和ROI有效性由现有 Overlay 再检查。

## 硬件接线约束

APB PCLK/PRESETn 与 `cnn_overlay_bridge` 的 result_clk/result_rst_n 相同。result_send/result_ready及帧号、valid、class、ROI逐一相连。pixel侧继续使用独立时钟；UART的叠加开关必须在帧边界同步之后进入 pixel_overlay_enable。

本接口不提供摄像头配置/采集控制，不能直接替换官方 common_apb3 后继续运行未经修改的 YOLO main。顶层仍需分配地址空间、实例化Sapphire、接入DDR仲裁、补齐预处理与UART控制，再由派生的 gesture main 调用。当前还没有将其注册到 Efinity 工程或连接 example_top，不能视为全链路已完成。

ROI右下边界为开区间，必须先完成摄像头到最终显示画面的几何映射。本模型只有类别，ROI不是预测检测框。AI复位清空邮箱；已显示旧结果由Overlay既有超时隐藏策略处理。

## 验证

运行 `python tools/run_cnn_result_apb_sim.py`。ModelSim 使用真实 `cnn_result_mailbox` 和异步14/10ns时钟，检查 APB setup无副作用、提交原子性、忙时拒绝、帧边界接收、影子写不撕裂、连续结果、错误地址/写值、valid=0失效及复位。

同一脚本用官方 RISC-V g++、实际 io.h/soc.h 编译调用方（RV32IM + Zicsr/Zifencei，-Wall -Werror），保存命令、日志和哈希于 `artifacts/cnn-result-apb-sim/report.json`。这些证明模块数字仿真及接口可编译；不是软件在板上运行、物理CDC收敛或HDMI验收。

组合接入模块见 [UART 与视频端点](CNN_UART_ENDPOINT.md)，连接 APB、真实结果邮箱、Overlay 和双开关状态同步；物理 example_top 与 Sapphire IP 实例化仍未完成。
