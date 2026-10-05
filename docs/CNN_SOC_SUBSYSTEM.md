# 官方 Sapphire 与 TinyML 子系统连接

阶段6实现中。`tools/generate_evsoc_subsystem.py`读取96MHz候选的实际Sapphire公共端口声明，及官方 `tinyml_accelerator_channels` 公共AXI声明，生成 `src/cnn/cnn_soc_subsystem.v`。源码及映射哈希保存在候选 `subsystem_ports.json`；检测到人工修改后的输出时停止覆盖。

## 已建立的连接

- 78个Sapphire端口全部有显式连接。CPU/内存/外设共用已经核对的96MHz用户时钟；io_systemReset / io_memoryReset / io_peripheralReset分别保留。
- 自定义指令的valid/ready/function/inputs/response和userInterruptA按官方edge_vision_soc实例接到官方TinyML模块；未使用的DMA中断userInterruptB明确为0。
- APB1接 `cnn_video_endpoint`，包含实际手势结果寄存器/跨域邮箱/Overlay。生成BSP的基址为0xF8100000。
- CPU合并地址接口、TinyML完整AXI接口完整导出，含CPU响应ID和错误响应；没有照搬官方示例里未连接的CPU响应ID网络，也没有将其臆定为0。
- JTAG、SoC调试UART、SPI明确导出等待顶层接线。SoC调试UART不能与原UART命令发送器并接同一引脚；需要后续调试通道/复用方案。

ai_online仍是待真实就绪条件驱动的输入，不可硬绑1来假定模型已经初始化。顶层尚未实例化此模块，不能从外层连接代码推断DDR/上板已经可用。

## AI地址窗口

`cnn_axi_window.v`为一个未接入顶层的合并地址接口隔离层，每个AI主设备需独立使用。逻辑[0x00001000,0x04001000)映射为物理[0x04000000,0x08000000)，保留原视频低48MiB。映射是减逻辑基址再加物理基址，不能仅给原指针加64MiB。

一次仅接受一个未完成事务。支持16字节对齐、128位INCR非独占突发；检查整个突发范围、溢出、4KiB边界。非法读返回AW/ARLEN+1个零数据DECERR拍；非法写吸收对应数量数据拍后回一次DECERR，均不访问下游。合法事务保留响应ID/错误/byte strobes及回压。

此模块不是仲裁器或完整事务缓冲。尚需给CPU及加速器统一转换，使用官方互连或经过验证的共享仲裁，并在允许AI占用DDR前缓冲完整写突发、保证读响应容量。AI独立复位不能直接丢弃在途DDR事务；需要停接新请求和排空/隔离的复位协议，否则会拖停视频。模型FPS与FIFO容量必须最终实测，不由本测试证明。

## 验证范围

- 新外层六个自有RTL文件通过ModelSim语法编译，零错误/警告；没有提供虚假的Sapphire/TinyML功能模型。
- 尝试编译真实官方Sapphire/TinyML IP失败：本机ModelSim 10.6e对Efinix加密区报syntax error in protected region，日志位于候选subsystem-check/vlog.log。这不是完整SoC仿真通过；需在Efinity官方综合/实现流程中继续验证。
- `python tools/run_cnn_axi_window_sim.py`通过首/末合法地址、突发跨上界、低于下界、地址溢出、4KiB跨界、非对齐/非法size/burst/lock、非法写吸收、响应ID及回压检查。零错误/警告。

后续实际工作：共享DDR事务缓冲/仲裁与复位隔离、Sapphire/TinyML/窗口/端点接到example_top、注册官方依赖并用Efinity综合，然后完成RAW8输入与匹配的软件主循环。不能将当前外层语法或窗口仿真当作完整系统完成。
