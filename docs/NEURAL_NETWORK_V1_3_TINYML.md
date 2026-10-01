# v1.3：按 EVSoC 手册迁移至 Jupyter 与 TFLite

日期：2026-10-01。只修改 CNN 副本，未合并主工程，未连接开发板。

## 路线纠正

当前主路线为 **Jupyter Notebook → TensorFlow/Keras → 全整数量化 TFLite → 厂商 TinyML Generator → Sapphire RISC-V / TFLite Micro / 可选 Lite 加速**。

v1.1/v1.2 的自定义 INT8 HEX 和 `gesture_shared_cnn.v` 是另一种专用硬件实现，不能直接加载 `.tflite`，也不等同于 TFLite 的 scale/zero_point、逐通道权重量化和 requantization。保留其历史结果与图像采集参考，但不再把它作为符合本次 TinyML 要求的部署成果。当前 `example_top.v` 仍是旧实验顶层，尚未接入 v1.3 SoC；没有新 TinyML bitstream。

主要依据：

- [EVSoC TinyML 用户手册](resources/1_3_EVSOC_tinyml用户手册_0416.pdf)：3.4.2 模型导入及软硬件参数生成；3.4.3 训练后全 INT8 量化。PDF物理页17–28、34–35，印刷页12–23、29–30。
- [厂商模型转换说明](../tinyml-main/docs/model_conversion.md)、[模型示例](../tinyml-main/model_zoo/README.md)、[Generator说明](../tinyml-main/tools/tinyml_generator/README.md)。
- [用户分享的分析](https://chatgpt.com/share/6abcf998-1fd0-83e8-80ef-e9826aa27769)：已读取正文。采用视频与AI支路分开、共享DDR3、分阶段验证、按需启用加速的建议。

手册约束的是模型格式、量化及部署流程，并非要求固定使用192×192、固定类别数或某一个演示网络。`创建和导出模型` 中的代码仅随机初始化一个卷积示例，并使用随机校准样本，不能当成训练完成的手势模型。本版使用真实手势数据训练和校准，不复制该随机示例作为结果。

## TensorFlow 与 PyTorch 的选择

| 项目 | TensorFlow/Keras | 现有 PyTorch conda |
|---|---|---|
| 本机核查 | TF 2.16.2 / Keras 3.15.1，项目内 Python 3.12 | Python 3.9.25，Torch 2.0.1+cu118 |
| GPU | 当前原生Windows环境运行CPU | 已检测到RTX 4060 Laptop GPU，CUDA可用 |
| 到板卡模型 | 官方 TFLiteConverter 直接输出 | 需转换并额外核对布局、算子及量化误差 |
| 本轮用途 | 主训练、量化、验证和Notebook内核 | 保留，后续较大模型GPU实验备选 |

选择 TensorFlow 是为了先打通手册规定的导出链，不是认为 PyTorch 不能部署。厂商文档包含 PyTorch→ONNX→TensorFlow→TFLite 路线；Google 也提供 [LiteRT Torch](https://github.com/google-ai-edge/litert-torch)。但较新的转换器能生成TFLite，不代表本地较旧的TFLite Micro和厂商加速内核一定兼容。

[TensorFlow官方安装说明](https://www.tensorflow.org/install/pip)指出原生Windows的CUDA支持止于TF2.10，较新版本GPU路线为WSL2。本轮不降级、覆盖现有PyTorch环境，也不自动改造系统WSL。后续训练性能不足时，可另建WSL2 TensorFlow环境，仍以同一TFLite契约验证结果。

## 已执行的 Notebook 与模型

- [01 分类器](../ml/tinyml/notebooks/01_gesture_classifier.ipynb)：从已有真实训练权重继续微调5轮；64×64×1灰度，拳头/剪刀/布/OK/点赞/非目标手势六类。
- [02 检测器](../ml/tinyml/notebooks/02_hand_detector.ipynb)：MobileNetV1 alpha=0.25前五个深度可分离块，接上下文卷积与手框头；256×144灰度，32×18网格。参考厂商MobileNet算子路线，使用ImageNet预训练初始化再训练HaGRID手框；并非厂商提供的预训练手检测模型。
- [03 中断恢复](../ml/tinyml/notebooks/03_resume_detector.ipynb)：原运行完成3轮冻结骨干及25轮微调后中断，从保存检查点再微调2轮并继续转换/评估。优化器重新建立，明确属于权重续训。

检测器将RGB首层卷积的三个输入通道权重相加，等价于重复灰度为RGB时的第一层结果。输入归一化在软件侧明确为 `(gray-128)/128`，训练、校准、PC推理保持一致。模型不包含依赖Python的运行时预处理。

分类器当前独立测试集1225张：FP32准确率94.0408%，TFLite INT8准确率93.7959%，两者argmax一致率99.5102%。TFLite文件20,408字节。该数字是**手部裁剪分类**准确率，不是全画面检测召回或实拍性能。验证集选择的logit差门限为1.5；不能沿用旧HEX引擎门限768或把logit差称为概率。

分类器部署文件：[gesture_classifier_int8.tflite](../ml/tinyml/artifacts/classifier/gesture_classifier_int8.tflite)。报告：[validation_report.json](../ml/tinyml/artifacts/classifier/validation_report.json)、[tflite_contract.json](../ml/tinyml/artifacts/classifier/tflite_contract.json)。

检测器结果已写入 `ml/tinyml/artifacts/detector/validation_report.json`。只用验证集选择阈值；最低离线门槛为候选框IoU≥0.5的精确率85%、有手场景召回50%。未过门槛时保留兼容性实验文件，不能发布为可用全画面识别模型，也不读取测试集调参。单手最高分方案不是多手同时检测。

## 导出契约与验证

1. 480张真实训练样本作校准；验证集用于模型/阈值选择；不以随机数替代实际图像，不拿测试集作校准。
2. TensorFlow官方转换器配置 `Optimize.DEFAULT`、`TFLITE_BUILTINS_INT8`、INT8输入输出。使用冻结的推理ConcreteFunction处理当前Keras3兼容性，仍由官方转换器生成FlatBuffer。
3. 检查输入输出shape、scale/zero_point、中间张量类型和算子清单。INT32偏置/shape常量是正常全整数量化组成，不要求每个常量都是INT8。
4. 检测器的物体分数与四个坐标使用不同输出张量，避免大范围logit压低坐标精度；输出顺序按实际shape识别，不猜测索引。
5. 使用PC TFLite Interpreter验证，再执行本地厂商 `tflite.exe` 分析。解析通过只证明其解析能力，**不证明目标TFLite Micro的AllocateTensors/Invoke或加速数值正确**。

分类器算子为4×CONV_2D、RESHAPE、FULLY_CONNECTED，无Flex、浮点回退或自定义Python算子。其输入scale=1/128、zero_point=0，当前灰度量化恰好等于gray−128；其他模型必须读取各自实际参数，不能普遍假定如此。

## TinyML Generator 输出与资源

`tools/generate_tinyml_v1_3.py`调用未修改的厂商Generator实现，生成 `defines.v`、`define.h/.cc`、模型 `.h/.cc`。使用项目内PyQt6执行，不改动原始示例。结果目录为各模型的 `generator/lite_p1`、`lite_p2`、`lite_p4`。

分类器加速器单独估算：

| Lite并行度 | LUT | FF | ADD | RAM10 | DSP |
|---|---:|---:|---:|---:|---:|
| 1 | 1017 | 1106 | 1105 | 8 | 19 |
| 2 | 1617 | 1706 | 1905 | 12 | 27 |
| 4 | 2817 | 2906 | 3505 | 20 | 43 |

AXI_DW=128，卷积Lite，FC Lite，未用ADD/MUL/MINMAX关闭，TinyML cache关闭。优先评估并行2，最终以CPU软件基线和逐层profiling决定。以上**不含CPU、DDR、视频、互联、Tensor Arena**，不是整板资源报告。检测与分类共享加速器时需要统一算子配置及参数上限，不能把两套不同defines分别塞进同一个实例。

## 与现有工程的接入安排

保留AR0135→DDR3→ISP→HDMI路径；AI从摄像头灰度支路取得低分辨率完整帧，或从具有明确所有权的DDR帧读取。Sapphire运行TFLite Micro、调度检测/裁剪/分类；结果通过有帧编号的状态邮箱交给既有GUI串口控制。AI繁忙时跳帧，不能阻塞无backpressure的视频显示链。

需要核对和落实的工程边界：

- 官方EVSoC手册以HyperRAM套件为例；本地 `tinyml_hello_world/Ti60F225_tinyml_helloworld` 已含DDR3控制器和三主机AXI互联，可作为移植起点，但配置为I3、含旧时钟/引脚及遗留HyperRAM注释。当前图像工程为C4，必须沿用实际板卡引脚并重新验证。
- 共享现有DDR控制器，增加CPU/AI访问仲裁、突发长度/ID/宽度适配、显示带宽保障和缓存一致性。不能直接把额外AXI主机接到当前读写复用端口。
- 分配不与帧仓库重叠的模型、arena和输入区；按实际AllocateTensors记录内存使用，而不是照搬手册示例10MB或把arena全放片上RAM。
- 固定图片的Micro推理先于摄像头接入；软件结果、加速结果和PC参考逐值比较后，才接GUI启停、过期清除、结果回传。
- 摄像头和裁剪要保持同帧或明确标识跨帧；快速运动、画面边缘、小手、遮挡、背景误报分别测量。

分享分析提到旧Sobel约50个RAM，不适用于当前已迭代图像工程。资源预算以本地现有报告为准，不能承诺示例中的5–15 FPS或其他模型只需换权重即可实时运行。保留将来OCR/人脸/物体功能的分时模型接口，不在本轮扩大类别。

## 运行与尚未验证项

双击 [start_notebook.bat](../ml/tinyml/start_notebook.bat)，使用 `CNN TensorFlow (project)` 内核。已安装的conda PyTorch环境不受影响。完整包版本记录在 [requirements.txt](../ml/tinyml/requirements.txt)。

```powershell
.\ml\.venv\Scripts\python.exe ml\tinyml\run_notebook.py ml\tinyml\notebooks\01_gesture_classifier.ipynb
.\ml\.venv\Scripts\python.exe ml\tinyml\run_notebook.py ml\tinyml\notebooks\02_hand_detector.ipynb
.\ml\.venv\Scripts\python.exe tools\generate_tinyml_v1_3.py ml\tinyml\artifacts\classifier\gesture_classifier_int8.tflite --out ml\tinyml\artifacts\classifier\generator
```

02会重新训练；03是本次已中断运行的恢复记录，不应当作每次都需要执行的常规步骤。

目标RISC-V软件编译、目标Micro算子执行、Sapphire接入、整板综合/时序、开发板实测尚未完成。当前PATH及已检查工具目录未发现 `riscv-none-embed-g++`；还需核对本地参考运行库依赖完整性。当前没有开发板连接，不生成“已上板识别”的结论。

## 本轮最终离线结果与继续事项

恢复Notebook已执行完成。MobileNet候选导出48,024字节TFLite，能够被厂商解析，但IoU50场景召回仅3.47%，不采用为部署模型。

进一步运行 [04 框尺度优化](../ml/tinyml/notebooks/04_detector_box_refinement.ipynb)，使用已有五层训练检查点，先把膨胀3×3等价展开为普通5×5卷积，再做12轮相对框误差优化；等价展开在验证样本上的浮点输出误差检查通过。最终生成30,616字节、仅普通CONV_2D算子的全INT8检测器。它在628张验证输入（432张完整有手图片、196张背景裁剪）上，门限−128 Q8时正确定位183张，候选精确率58.47%、场景召回42.36%，仍未通过部署门槛。测试集未用于该检测器调参。

[05 两阶段验证](../ml/tinyml/notebooks/05_pipeline_validation.ipynb)已使用真实1280×720验证图片执行TFLite定位→动态面积平均裁剪→TFLite分类。门限−128时432帧中接受117帧，其中88帧同时满足类别正确和IoU50，严格精确率75.21%、严格帧召回20.37%。不是视频或板卡数据，且缺少真实全场景无人手视频的误报统计。

这说明问题目前主要在检测与裁剪覆盖率，不能拿分类器93.80%的准确率代表整套任意位置手势识别。下一轮优先细化检测网格、小手尺度分布、定位标签/损失和裁剪覆盖率，使用冻结验证划分比较；未达标不发布新部署bitstream。

已生成 [共享加速器参数](../ml/tinyml/artifacts/shared_generator/profiles.json)，取检测与分类所需算子及缓存参数上限，一套Lite P1/P2/P4配置可分时服务两者；仍未综合。

已生成 [固定图片目标验证包](../firmware/tinyml_gesture_v1_3/README.md)，包含分类器模型、厂商Lite P2配置、8组精确INT8参考值以及调用AllocateTensors/Invoke的应用层。SDK依赖审计发现imgc示例缺少整数参考头；与同包kws示例核对453个共有TensorFlow文件全部字节一致后，已将11个缺失头复制到独立vendor_overlay并记录来源哈希，未修改原始厂商示例。后续编译需添加此overlay包含路径。RISC-V编译器、目标执行、SoC移植和硬件验证仍待完成。
