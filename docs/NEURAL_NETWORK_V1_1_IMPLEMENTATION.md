# 神经网络手势识别 v1.1（2026-09-30）

## 当前状态

已完成公开数据处理、浮点训练、自定义 INT8 量化、Python/RTL 逐层一致性验证和 GUI 开关接口。FPGA 综合/布局布线状态见本文末尾的编译记录。开发板未连接，尚未进行下载、AR0135 实拍或串口联调；公开数据准确率不代表实拍准确率。

所有修改位于 `C:/Users/francis/Desktop/fpga-w.-codex-cnn`，主工程保持独立。新增备注使用 v1.x，旧 v0.x 历史不重新编号。

## 本轮架构与资源选择

AR0135 原始灰度 → 中央 512×512 区域 → 8×8 区域平均 → 64×64 灰度 → 四层卷积/ReLU → 六类分数 → 门限拒识/连续两次确认 → UART → GUI。

五个目标类别依次为拳头、剪刀、布、OK、点赞；第六类 `no_gesture` 用于拒识，不作为第六种显示手势。模型没有全画面手检测器：手应放在画面中央区域，约占区域宽高的三分之二，保持单手且完整可见。ROI 在原始 1280×720 图像的 `(384,104)` 起始，宽高均为512；显示侧缩放、旋转、ISP、DDR回放不会改变识别源。

本轮选择 FPGA 共享 INT8 乘加器，未引入整套 RISC-V SoC。TinyML 是部署方式/工具生态，并非额外的免费硬核；软核和加速器也会消耗逻辑、RAM和DSP。此实现独立于CPU与DDR，不占现有帧缓存带宽。当前模型为初步可优化基线，未来增加文字/人脸/物品等任务需要重新核算算力、存储、模型和输入管线，不能把剩余逻辑百分比直接当作可容纳模型数量。

| 层 | 输入→输出 | 权重数 | MAC数 |
|---|---|---:|---:|
| Conv3×3/s2 + ReLU | 64×64×1→32×32×8 | 72 | 73728 |
| Conv3×3/s2 + ReLU | 32×32×8→16×16×16 | 1152 | 294912 |
| Conv3×3/s2 + ReLU | 16×16×16→8×8×24 | 3456 | 221184 |
| Conv3×3/s2 + ReLU | 8×8×24→4×4×32 | 6912 | 110592 |
| FC | 512→6 | 3072 | 3072 |

共703488 MAC/次；INT8权重14664字节，INT32偏置344字节。特征缓冲两组8192字节，ROI4096字节。RTL仿真每次推理1462290周期，96MHz下为15.2322ms（仅计算，不含等待摄像头、两次确认及GUI轮询）。实际RAM块消耗由综合报告确定，不能用字节简单除块容量代替。

## 数据、训练和量化

数据来源、许可和派生规则见 [DATA_SOURCES.md](../ml/gesture/DATA_SOURCES.md)。共4800张来源图片处理成功。额外原图哈希审计发现1个跨组哈希，排除对应3个原始ID的全部8个派生负样本（训练2、测试6）。最终按人员、原始ID及原图SHA256均不跨组；同一图片的手部/背景裁剪保留在同组。排除记录见 `ml/gesture/data/excluded_cross_split.json`，检查结果见 `ml/gesture/artifacts/data_integrity.json`。

| 分组 | 每个目标手势 | 无手势/背景 | 合计 |
|---|---:|---:|---:|
| train | 608 | 3110 | 6150 |
| val | 72 | 370 | 730 |
| test | 120 | 625 | 1225 |

TensorFlow2.16.2、Keras3.15.1，seed1101，CPU训练；训练60epoch，保存验证准确率最好的模型。采用水平翻转、小幅旋转/平移/缩放、亮度/对比度扰动和类别权重。验证集用于检查点和拒识门限选择；量化校准只使用训练集，测试集不参与选择。

将BN折入卷积，权重有符号INT8，偏置INT32，隐藏激活0..127，层尺度为2的幂；输入为 `gray_uint8-128`。3×3/s2 SAME在偶数尺寸下上/左不补、下/右补1个零。舍入为加半个量化单位后算术右移（半值向正无穷）。最终六个logit为有符号16位Q8。它是已与RTL核对的自定义定点格式，不是TFLite文件，也不声称兼容TFLite解释器。

| 指标（独立测试集1225样本） | 结果 |
|---|---:|
| 浮点整体准确率 | 89.22% |
| INT8整体准确率 | 88.98% |
| INT8 macro-F1 | 87.59% |
| 浮点/INT8分类一致率 | 98.12% |
| INT8拳头召回率 | 96.67% |
| INT8剪刀召回率 | 95.00% |
| INT8布召回率 | 94.17% |
| INT8 OK召回率 | 84.17% |
| INT8点赞召回率 | 91.67% |

门限仅由验证集选定为 top1-top2 ≥768（Q8数值，即3.0），同时top1必须是五个目标类之一。独立测试接受375例，375例正确；600个目标手势中375例被正确接受（62.50%），其余225例被拒绝；625个负样本未发生错误接受。这仅是有限测试集上的观察，不能推断实拍零误识别。门限较保守，接受率仍需优化。连续两帧确认是硬件稳定策略，上述单张公开图像测试没有测量它对真实视频的效果。

首轮结果因发现跨组重复原图而作废，完整记录备份于 `tools/debug/before-v1_1/hash_audit`。本表对应排除重复原图后从头训练、重新量化的结果；网络结构、训练超参数和门限选择规则未按测试结果调节。

完整混淆矩阵及量化数据见 `ml/gesture/artifacts/validation_report.json`。OK类和背景拒识仍是主要改进方向。后续以AR0135实拍补充数据，按采集人员/会话独立划分，优先检查光照、比例、角度和背景差异；不要靠重复查看测试集调门限。

## 硬件接口及GUI

打开 `host/start_gui.bat`（优先使用项目的 `ml/.venv`，包含pyserial），连接板卡真正的UART端口后，点击“手势识别”打开窗口，再点击启动/停止。启动后通过UART读取类别并显示中文结果。GUI每250ms轮询一次，无法将15.23ms计算时间当作GUI响应时间。旧固件不支持新协议时功能按钮不可用。

未连接板卡时可运行 `host/start_gui.bat --demo` 检查界面与按钮；模拟模式明确显示未产生识别结果，不生成假预测。GUI当前没有接入HDMI图像采集，结果文本通过UART展示，摄像头画面仍经板端HDMI观看。

- CMD `0x40`：无payload，读取状态。
- CMD `0x41`：1字节，bit0启停，其余位必须为0；GUI控制后再次查询实际状态。
- 回复8字节：status、版本`0x11`、flags、class、margin低/高字节、frame低/高字节。
- flags：bit0启用、bit1推理忙、bit2有效结果、bit3模型存在、bit4过期。
- class：0拳头、1剪刀、2布、3OK、4点赞；无有效结果为`0xFF`。
- 连续两次接受同类别后显示；拒识立即清除，0.5秒无新结果过期，关闭/重新启动清除历史。恢复默认同时关闭识别。
- ROI用请求/应答翻转位跨时钟域交接，推理期间保持整帧不变，忙时跳帧，不阻塞视频。

## 修改清单与验证

v1.1 / 1–3：数据准备、训练、BN折叠/量化导出；4–6：CNN、ROI、调度/拒识；7–11：主机协议、摄像头灰度接口、顶层/工程文件和GUI；12–19：ROI/CNN/UART/调度仿真、Python测试、构建脚本和模拟默认状态；20：GUI启动器优先项目环境；21：修正数据署名说明；22：补齐Efinity构建环境配置变量；23：独立同步读寄存器修正特征RAM推断；24：真实双时钟ROI→CNN联动仿真；25：原图哈希跨组去重和训练入口校验；26：编译输入/输出哈希与时序验收清单。

原文件备份位于 `tools/debug/before-v1_1`。

已验证：CNN 8组输入（六类各一张以及全0/255边界）共114688个中间激活和48个logit逐值一致；调度测试覆盖确认、换类、拒识、过期、关闭/重启；主机25项测试通过。新增两个完整模拟摄像头帧经实际ROI、跨时钟交接和CNN核对分数及确认状态，不使用强制内部推理结果。上轮ROI逐像素采样测试、UART新命令测试和现有摄像头/UART回归通过；本轮编译记录另列。

复现命令（在CNN目录执行；重训会覆盖当前模型，请先备份需要保留的artifacts与ROM）：

```powershell
.\ml\.venv\Scripts\python.exe ml\gesture\prepare_hagrid.py
.\ml\.venv\Scripts\python.exe ml\gesture\train_v1_1.py
.\ml\.venv\Scripts\python.exe ml\gesture\export_v1_1.py
.\ml\.venv\Scripts\python.exe tools\run_gesture_sim.py cnn
.\ml\.venv\Scripts\python.exe tools\run_gesture_sim.py roi
.\ml\.venv\Scripts\python.exe tools\run_gesture_sim.py pipeline
.\ml\.venv\Scripts\python.exe tools\run_gesture_sim.py integration
.\ml\.venv\Scripts\python.exe tools\run_gesture_sim.py uart
.\ml\.venv\Scripts\python.exe -m unittest host.test_gesture host.test_host host.test_advanced_isp host.test_snapshots
.\ml\.venv\Scripts\python.exe tools\build_gesture.py
```

构建脚本仅生成bitstream，不启动下载器。新输出在 `outflow_v1_1`；旧outflow中的bit文件不包含本轮CNN，不能用于验证此功能。

## 编译记录

最终权重已通过Efinity2026.1的map、interface、pnr、pgm全部阶段。生成文件：`outflow_v1_1/Ti60_AR0135.bit`（2407254字节），可供后续连接板卡后下载。没有执行下载器或串口操作。

| 项目 | 最终完整工程 | 板卡容量 | 占用 |
|---|---:|---:|---:|
| XLR | 18479 | 60800 | 30.39% |
| RAM10块 | 125 | 256 | 48.83% |
| DSP块 | 18 | 160 | 11.25% |

层级报告估算手势模块本身为3256 XLR、38块RAM、1个DSP。相对历史视频工程15199 XLR/87RAM/17DSP，总工程增加3280 XLR/38RAM/1DSP；历史基线并非本轮重编，因此逻辑增量只作对照，模块层级和本次总报告更直接。

最小setup slack为+0.158ns，最小hold slack为+0.026ns；96MHz系统域setup slack为+0.308ns。所有报告中的setup/hold时钟关系均为正值，CDC报告无Synchronizer warnings。静态时序沿用原工程约束和跨域例外，不等同于已完成板端电气/传感器/DDR实测。编译保留原工程的未使用接口端口等告警，未修改现有IO布置。

bitstream SHA256：`d2376a300f49482ffc295fef7516a7eb7392dc8ee38ca9b577e786a612933700`。
量化模型JSON SHA256：`f04b40986caf72337365f869980a0eaf0ca6de345c6e178c8b3f0ddc89815573`。

`outflow_v1_1/build_manifest.json`记录实际参与构建的源码/ROM哈希、输出哈希、时间与时序验收；构建过程中输入变动或存在负slack时脚本拒绝标记完整成功。`ml/gesture/artifacts/release_manifest.json`关联数据、模型、验证日志和最终bitstream。旧 `tools/debug/before-v1_1/hash_audit` 中的首轮模型结果仅供追溯，不用于部署。

上板待办：连接电源、AR0135、HDMI、JTAG及UART；下载本次bitstream；GUI启动后测试五类/空背景/移出ROI/遮挡/断流/反复启停；收集不同人员和光照实拍，评估误识别、拒识和完整交互延迟。当前公开模型要求中心ROI，尚未实现全画面定位、多手识别或任意距离识别。
