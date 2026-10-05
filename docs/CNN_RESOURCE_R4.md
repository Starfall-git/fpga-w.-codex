# r4：4×4 卷积资源优化与参考后端对齐

对应阶段6子步骤：静态 INT8 上板验证及加速器资源配置。实时摄像头推理、Overlay 与端到端15FPS仍待验证。

## XLR 分布与配置

XLR是整个FPGA设计占用的逻辑资源，并非TinyML专用资源。r3的PNR层级报告显示：总计57739/60800，TinyML加速器27425，Sapphire CPU9496，DDR控制器5045，视频AXI控制4044，图像控制3719，视频处理4819。其余为互联、结果接口等逻辑。层级报告存在父子包含关系，不能重复相加。

通过未修改的官方2026.1 TinyML Generator生成两组配置。保持Conv STANDARD、Cache ENABLE/1024和Reshape STANDARD；ADD/LR/MUL/MIN_MAX原本已经DISABLE。保留现有视频功能，通过调整FC来恢复4×4卷积。原版FC STANDARD约4029.5 XLR，Lite约947 XLR。

|配置|XLR|余量|RAM10|DSP|同一旧ELF的三组Invoke耗时(ms)|
|---|---:|---:|---:|---:|---|
|r3：2×2 + FC STANDARD|57739|3061|233|53|173.657 / 173.614 / 173.648|
|4×4 + FC LITE|59801|999|244|65|70.724 / 70.650 / 70.646|
|4×4 + FC DISABLE|58819|1981|240|57|70.978 / 70.834 / 70.902|

三组使用相同ELF SHA256 `694ff2a91c8a9f9811fb32af5479da1799ad969c633c587e5c9d4fba0132ff47`，每次五个ELF段回读全部matched。硬件配置通过GDB读取`hw_accel_setting`确认：4×4且FC为Lite(1)或Disable(0)。三组方案的输出相同。

4×4使本模型整次Invoke约快2.45倍。输入×输出并行度由4个组合增加到16个组合，但首层通道数、DDR、缓存和CPU算子会限制实际收益。FC只有1024×3个乘加，关闭其硬件加速后由官方软件路径执行，实测仅增加约0.23ms，却比Lite再释放982 XLR。因此选择FC DISABLE作为动态链路候选。约70.9ms对应14.1次静态推理/秒，尚未达到15FPS的66.7ms预算，也未包含采集与显示。

两个候选的map/interface/pnr/pgm均通过。Lite的clk_sys setup +0.171ns，Disable为+0.157ns；JTAG跨域仍分别为-0.403/-1.307ns与-0.290/-1.297ns。属于用户授权的调试版本，不能称为时序签核完成。

## ±1差异的独立复现

模型未改变，SHA256 `7891518a9b70ec6b3be8649123651780ce87ede1e69a9a49c394c17d203a0baa`。在TensorFlow2.15.1下重新运行冻结的372张评估集：

- 默认解释器创建XNNPACK delegate，完整复现原v0.3全部输出。
- BUILTIN_REF相对原输出有46个元素相差1；所有预测类别一致，准确率仍95.43%。
- 关闭默认delegate的builtin模式有45个元素相差1，类别及准确率同样不变。参考模式与无delegate模式并非所有372张逐字节相同，不能混用这两个基准。
- 三组板端输入在这两种无delegate模式下恰好输出相同，均为`[11,0,-2]`、`[-1,78,-60]`、`[1,-74,63]`，与板端逐字节一致。

证据支持原来的两处±1是桌面执行后端与目标参考路径之间的数值差异；尚未定位到具体算子内部舍入步骤。不是通过放宽误差阈值来通过验证。原XNNPACK golden和旧ELF全部保留，新增独立的BUILTIN_REF基准及派生`evsoc_tinyml_gesture_reference`验证应用，只更新期望输出，模型、输入、推理runtime及严格比较保持一致。桌面372张准确率不代表已完成372张板端测试。

## 复现与工程入口

Efinity工程：`artifacts/evsoc-4x4-fc-disable-map/Ti60_AR0135.xml`。同级`board-comparison-r1`为旧ELF对比证据，`board-reference-r1`为参考基准验证证据。Lite候选为`artifacts/evsoc-4x4-fc-lite-map`。原`fpga-w.-codex`未修改。

教程侧`audit_int8_backends.py`独立生成参考报告；`generate_official_tinyml.py --in-parallel 4 --out-parallel 4 --fc-mode DISABLE`调用官方Generator。FPGA侧`prepare_reference_validation.py`建立派生应用，官方RISC-V make构建；`measure_evsoc_candidate.py`执行JTAG易失性下载、ELF回读及定时验证，保留完整日志和哈希。

调试服务无响应时要先分层检查：本轮最初器件ID可读但DMI超时；重新下载已验证r3 `.bit`后CPU连接恢复。未以增加超时掩盖DMI问题，也未写Flash。

## 调试包使用

使用`deliverables/v0.5-ti60-debug-r4`内配套文件。关闭其他JTAG会话后，用Programmer的JTAG模式下载`hardware/Ti60_AR0135.bit`。运行`start-openocd.ps1`，确认CPU examined；再在第二个PowerShell运行`start-gdb.ps1`。预期`CNN_RESULT 1195655729 9 0 3 3`，表示三组输出严格匹配本包明确标注的BUILTIN_REF基准。

启动器将GDB正常stderr保存为日志，检查真实退出码及五段matched，下载180秒、运行60秒超时。静态固件未设置实时firmware_ready；host推理控制不可用是预期，不应把静态测试当成摄像头推理或Overlay已经完成。
