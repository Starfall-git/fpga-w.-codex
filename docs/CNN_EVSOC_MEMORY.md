# 官方AXI转换器与SoC共享内存接线

阶段6的子步骤：完成官方转换器派生适配、协议组合仿真及SoC内存封装代码。尚未完成example_top接入、Efinity综合或上板验证。

## 官方代码来源

`artifacts/evsoc-system-r1/official_source/axi/axi_full_to_half_duplex.v`来自官方YOLO EVSoC示例，SHA256 a43794ba12a01484d794cf9575e1819a0a844d60dd538f789d6cd900957f00af。派生文件src/cnn/cnn_axi_full_to_half_duplex.v保留完整MIT许可，仅重命名模块、增加io_ddr_b_payload_resp输入并将其传给s_axi_bresp。官方原文件未修改。原版固定返回OKAY，会吞掉窗口DECERR，故不能原样用于隔离内存通路。

## 实际子系统连接

`cnn_evsoc_memory.v`实例化真实cnn_soc_subsystem、派生转换器和cnn_shared_ddr，CPU的combined AXI接lane1，TinyML完整AXI经转换接lane2，video物理地址接lane0。CPU/TinyML各自的原8位ID及响应保留；TinyML原IP不接收BID/RID，按其官方接口处理。所有内存端口必须处于clk_96域。

fabric_rst_n只能来自共享DDR全局复位。AI/system/memory/peripheral复位触发两个隔离端口abort，不能复位仲裁器；父顶层需保持AI复位并等待ai_quiescent再释放重启。封装不提供父层复位时序器、不含摄像头DMA、未将ai_online强行置1。视频端口已留出，尚未接example_top的AWARMux/DdrCtrl。

生成器tools/generate_evsoc_memory.py根据现有真实公开端口生成接线；重新运行会覆盖派生封装，请先保存人工修改。

## 验证证据与范围

1. run_cnn_axi_adapter_sim.py：AW/AR同时请求、官方写优先、地址停顿、四种B/R响应、ID/data/strobes和复位，通过；ModelSim零错误/警告。
2. run_cnn_adapter_shared_ddr_sim.py：真实转换器+完整缓冲+窗口+仲裁组合，CPU256拍写途中abort、TinyML读消费者长时间停顿，视频完成350次读取；另发TinyML越界写，窗口DECERR经转换器正确返回，未进入DDR。零错误/警告。读取次数不是帧数或FPS。
3. cnn_evsoc_memory外层vlog语法编译零错误/警告；这不等于真实加密Sapphire/TinyML完成elaboration。既有ModelSim不支持官方加密区域，完整验证需Efinity综合。

下一步将封装接example_top，处理JTAG/SPI/调试UART引脚与AI复位排空，登记IP/源文件/约束后走官方综合；随后验证视频FIFO/带宽、RAW8预处理与固件主循环。阶段6/7仍未完成，无新板卡下载。
