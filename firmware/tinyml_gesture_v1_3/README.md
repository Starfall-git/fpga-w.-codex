# v1.3 固定图片目标验证包

此包已生成真实TFLite模型、厂商Lite P2参数及8张真实图片的INT8输入/输出参考。`src/main.cc`按本地参考项目的MicroInterpreter API编写，**尚未交叉编译、未在开发板执行**，也不包含Sapphire顶层和GUI实时数据通路。

在独立副本中以 `tinyml_imgc` 软件工程为模板，保留其BSP、TensorFlow Micro、平台算子及中断代码，用本包的main和model文件替换应用层。RTL使用同包的defines.v；软件和硬件设置必须配套。不要向其他主项目直接复制。

目标运行先检查schema、INT8尺寸和AllocateTensors，再执行8次Invoke并与PC原始INT8 logits逐值比较，输出arena实际使用量和mismatch数量。64KiB arena只是待验证的初始预算，应链接到不与视频帧重叠的外部RAM；不可把它当作已测内存或片上RAM资源。若不一致，先排查运行库版本、优化算子、量化、缓存与输入字节，不能仅按类别一致放行。

生成入口：`ml/.venv/Scripts/python.exe tools/package_gesture_tinyml.py`。清单记录模型与文件哈希。

当前前置缺项：已检查工具目录与PATH未找到 `riscv-none-embed-g++`；imgc参考工程缺失的11个整数参考头已从同包kws版本恢复到vendor_overlay（453个共有文件字节一致），编译时将 `-Ivendor_overlay` 加到包含路径。需采用与该参考工程匹配的SDK和依赖，再进行软件构建；不能用PC TFLite通过替代该验证。
