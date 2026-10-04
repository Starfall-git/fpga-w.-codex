# 实际 DDR3 视频工程的 SoC 候选目录

阶段6的候选目录 `artifacts/evsoc-system-r1` 由 `tools/prepare_evsoc_system.py` 从本独立副本当前 example_top / Ti60_AR0135 XML / peri / src / sdc / ip 复制。官方来源为已派生的2026.1 YOLO EVSoC工程，官方 source 文件保持许可证及原内容存放于候选 official_source。原始 fpga-w.-codex 不参与写入。

## 时钟与内存

实际 example_top 的 `w_ddr3_ui_clk = clk_sys`，CLOCK_MAIN=96000000。DDR物理时钟与AXI用户时钟不能混用；本轮配置SoC CPU、peripheral为96MHz，memory端接同一个96MHz用户时钟。最终必须验证生成IP时钟端口与SDC。

Sapphire保留官方128位合并地址DDR接口、自定义指令配置；APB0暂禁用、APB1启用用于手势结果窗口，摄像头I2C由既有FPGA链路负责。逻辑DDR窗口设置64MiB；计划通过受限地址转换映射到物理64–128MiB，保留原低48MiB视频存储。地址转换尚未实现，不能把当前软件地址直接送入DDR。CPU与TinyML必须使用一致转换、越界检查和有界仲裁，且不能改动原DDR行列参数来猜容量。

## 生成入口

设置 EFXIPM_HOME 为本机Efinity 2026.1的ipm目录，运行官方 bin/python3.bat：

```text
python3.bat tools/generate_cnn_sapphire.py artifacts/evsoc-system-r1 Ti60_AR0135.xml
```

参数检查、IP生成和BSP导出使用官方 IPMDesignAPI；第二个工程文件参数可省略，旧静态工程默认行为保留。仅在生成成功并检查RTL、模板、soc.h存在后输出PASS。日志generate.log及generate.exitcode保存在候选目录。

当前候选的example_top仍为原视频顶层加既有RAW8旁路，尚未实例化新Sapphire或cnn_video_endpoint；生成IP并不意味着顶层集成/编译/下载完成。下一步应核对模板并从官方edge_vision_soc实例提取SoC/加速器子系统，完成共享DDR总线、ID返回、地址分区和控制窗口接线。JTAG模式、软件启动地址及真实AI在线信号须与最终BSP一致。
