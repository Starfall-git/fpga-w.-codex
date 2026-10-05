# 真实顶层接入、资源约束与DDR3软件构建

阶段6实现中；完整实时推理、视频叠加及15FPS尚未验证。

## 本轮完成

`tools/integrate_evsoc_top.py`在独立副本的artifacts/evsoc-system-r1产生实际example_top工程：原视频AW/AR mux接共享DDR端口0；Sapphire CPU和TinyML接隔离端口1/2；DdrCtrl由唯一共享输出驱动。Overlay插入ISP输出和HDMI之间，RGB/HS/VS/DE一致延迟，命令UART的50/51已接实际requested/applied/available。纯视频根目录源码作为生成基线保留。USER1 JTAG按官方EVSoC配置复制，不占用猜测GPIO引脚。

SoC的SPI和调试UART物理连接暂未启用，不能用当前命令串口读取SoC printf。现阶段用JTAG加载/调试软件，命令UART继续独占原TX。原工程部分未使用LCD等输出仍有未驱动警告，不应当视作已清理全部引脚问题。

新增cnn_ai_reset等待DDR校准完成、缓冲排空后释放AI，兼容Sapphire延长复位与调试复位；共享DDR和视频不接受AI局部复位。APB 0x28写0x47535452报告固件就绪、写0清除、复位清零，其余写值SLVERROR。真实SoC启用REQUIRE_FIRMWARE_READY=1，只有硬件就绪且固件明确握手才允许推理。静态自检软件不设置该位，不伪装成实时摄像头推理。C接口为gesture_set_ready。

## 官方工具验证

Efinity/Elitestek 2026.1实际综合通过，包含真实Sapphire和加密TinyML，接口检查PASS。两个事务缓冲均映射为8个RAM10，总16个，没有被展开为数万寄存器。

|卷积输入×输出并行度|LUT4|FF|DSP48|RAM10|PNR打包XLR|结果|
|---|---:|---:|---:|---:|---:|---|
|4×4|38452|29559|73|240|63390|超过60800容量|
|2×4|37426|28675|65|235|61392|超过60800容量|
|2×2|35399|26944|53|233|57695|容量及PNR通过，时序未签核|

通过官方TinyML Generator重新选择并行度，未删除原视频功能；模型数组均与冻结INT8文件逐字节一致。最新配置保存在config/cnn，生成报告记录源码、分析器、模型哈希。硬件并行度影响吞吐，不能以容量通过推断15FPS。官方生成器输出TML_C0_RESHAPE_MODE，官方RTL使用TML_C0_RS_MODE，派生配置加入同值别名，未修改官方加密源码。

综合前修复XML源文件顺序/XSD约束、新增源使用sv_09，并登记官方完整source.f清单以满足加密模块中的依赖。保留4×4和2×4容量失败证据于候选history，避免重复尝试。

当前继承的视频SDC含被优化掉的clk_cam_feedback/clk_pixel_2x、cmos_data低位及DDR未使用输入的无效对象告警；须逐项结合实际网表核对。不能用错误约束下的工具结束状态宣称时序签核。未做下载。

## 软件与测试

基于官方YOLO派生的evsoc_tinyml_gesture已使用本候选真正生成的96MHz DDR3 BSP构建成功，非旧HyperRAM BSP。text780808、data77094、bss2365704字节，ELF SHA256 7a1f838430d4dac660de39a2e2bcbc01f60d4533575ed48018fda64b021acc32。保留TinyML初始化与Invoke，按本硬件不存在APB0的事实条件编译旧PiCam/DSI/DMA专用代码，保留加速器PLIC A中断并在main调用官方初始化。禁止给缺失外设伪造地址宏。此ELF仍是三组静态自检，未上板运行。

APB寄存器（含就绪握手、拒绝非法值、复位清零）、三时钟UART/Overlay端点（固件握手前不可推理、CPU复位后需重新握手）、AI复位排空测试均PASS，零错误/警告；C接口通过官方RISC-V编译。

## 后续

PNR session49440已exit0/PASS，耗时161秒，生成内部lbf文件；最差setup裕量为JTAG到clk_sys的-1.307ns，反向-0.384ns，需对照官方CDC审计约束后重新验证，不能直接宣称时序通过。下一步审计SDC/剩余资源/时序。实际720p读写/FIFO压力、RAW8 crop/resize/INT8输入、固件摄像头循环、显示坐标映射、板上golden和帧率验证仍需完成。阶段6/7保持未勾选。
