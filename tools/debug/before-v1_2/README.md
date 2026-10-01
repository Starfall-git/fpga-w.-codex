# FPGA 图像处理与神经网络工程

## 神经网络分支 v1.1（2026-09-30）

本副本用于神经网络搭建、优化与分析；新增备注使用v1.x，保留原v0.x历史，不修改主工程。

- [手势识别实现、训练/量化结果、验证及使用说明](docs/NEURAL_NETWORK_V1_1_IMPLEMENTATION.md)
- [v1.0板卡资源分析与方案规划（历史）](docs/NEURAL_NETWORK_V1_0_PLAN.md)
- [公开数据来源与许可](ml/gesture/DATA_SOURCES.md)
- [GUI使用说明](host/README.md)

已训练拳头、剪刀、布、OK、点赞及拒识类，导出INT8权重，并通过RTL逐层一致性检查。已完成Efinity编译和静态时序验收，bitstream在 `outflow_v1_1/Ti60_AR0135.bit`；尚未进行开发板实物验证。
