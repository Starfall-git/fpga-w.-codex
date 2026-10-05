# 现有 ELF 上板：r2 外部复位实验

当前任务仅为运行现有三组 INT8 自检 ELF。r2 位于 `artifacts/evsoc-debug-reset-r2`，由 `tools/prepare_evsoc_debug_reset.py` 从 r1 复制生成；已在连接的板卡上恢复CPU调试，但尚未通过ELF执行；不是正式验收版本。

## 改动及理由

两次完整100 kHz日志均在首次 DMCONTROL 写请求后持续Busy。为检验外部AI门控是否阻断调试，r2只将 `cnn_soc_subsystem` 内 Sapphire 的 `io_asyncReset` 从 `ai_reset` 改接全局 `!uart_rst_n`。本项目的uart_rst_n就是顶层rstn_sys。

`cnn_ai_reset` 状态机及共享DDR端口的abort门控仍保留。因此DDR未就绪或AI门控复位期间，CPU/TinyML的新访存不被接纳；已提交的事务按既有缓冲规则排空。Sapphire可以先解除外部复位并接受调试，CPU可能在尚未开放DDR时等待取指；需要板上检查才能证明此实验有助于当前故障。此版本不提供独立AI故障后自动重启CPU的完整恢复流程，不能替代后续系统复位设计验收。

ELF、96MHz配置、TinyML 2×2配置、模型与地址映射均沿用r1。ELF SHA256为 `694ff2a91c8a9f9811fb32af5479da1799ad969c633c587e5c9d4fba0132ff47`。

## LED解释

已查阅 `Ti60_Board_引脚定义-20230703-V1.0.xlsx` 及 `Ti60_F225_Core_V1.4.pdf` 第4页：LED0～5对应同编号led_o，LED6/7复用CMOS_D0/D1；八个LED均由3.3V经电阻、LED连到IO，低电平点亮。

r2默认映射：LED0灭=hardware_ready为1；LED1亮=AI门控ai_reset为0；LED2灭=DDR cal_done为1；LED3灭=DDR cal_pass为1。LED4/5保留摄像头配置/帧活动含义。正常稳定就绪时LED0灭、LED1亮、LED2灭、LED3灭。

## 验证与实际结果

准备脚本拒绝覆盖已有候选，复制官方IP及已有源码，保留原工程和r1。原有复位控制、共享DDR事务隔离回归均通过，ModelSim零错误/警告；它们验证保留模块的行为，不代表真实Sapphire调试跨域或板上推理通过。

官方 map/interface/pnr/pgm 全部通过。通过官方 FT232H JTAG 工具下载 r2 `.bit`，没有写 Flash。OpenOCD 已成功 examine/halt CPU；用户确认 LED0～3 为灭、亮、灭、灭。

GDB 报告传输858042字节，但 `compare-sections .init` 为 MIS-MATCHED，入口每16字节只有首个32位字正确，不能认定下载成功。进一步在0x003f0000/04/08/0c写入11223344/55667788/99aabbcc/ddeeff00，回读仅首字正确。硬件断点也不受本CPU配置支持，后续使用运行后halt读取状态的方式。

## r3：修正CPU带字节使能的写地址

官方生成文件 `ip/SapphireSoc/SapphireSoc.v` 的 BmbToAxi4Bridge 固定输出 AxSIZE=4，同时保留输入字节地址，使用 WSTRB 表示有效字节。原 `cnn_axi_window.v` 要求低4位为0，导致CPU在一个128位节拍中访问其他字通道时被本地拒绝。

修正窗口按16字节边界归一化下游DDR地址，数据及字节写使能保持原样；上界和4KiB检查也按实际节拍范围计算。仍拒绝越界、非INCR、非128位宽度和lock请求。新增四个32位通道、窗口最后字节、非对齐越界测试通过，原共享DDR中止隔离回归通过（347次视频读）。

r3候选在 `artifacts/evsoc-debug-lanes-r3`，复用r2复位接法和原ELF。构建及ELF逐段回读已通过。增加启动前reset halt后，现有ELF完成三组推理；严格逐值比较为1/3通过，其余各差1。详见 [r3实测及复现](CNN_ELF_RUN_R3.md)。
