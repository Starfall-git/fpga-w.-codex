# UART 独立推理与叠加控制

阶段6：`cnn_video_endpoint.v` 把 Sapphire APB 结果寄存器、结果邮箱和 Overlay 组合起来，并连接现有 `uart_image_control` 新增的两个开关。该组合模块已仿真，但尚未接入 example_top 或Efinity项目。原顶层的 CNN_ENABLE 默认为0，尚未声明板上支持此功能。

## 串口协议

沿用13字节 A5 5A/SEQ/CMD/DATA8/CRC8。新增 0x50 查询（全零payload）；0x51 设置（DATA0 bit0推理、bit1叠加，其他位与字节必须为0）。能力由旧 GET_STATUS 的 DATA6 bit5声明，原低5位不变。默认两个开关均关。

CNN应答DATA0..7为 status、applied、requested、available、ABI=1、0、0、0，applied/requested均使用相同两位。status=0成功、1CRC错、2参数错、3推理不可用、5应用等待超时。0x50/0x51的CRC错误也返回CNN格式。功能编译关闭时保持旧协议的未实现应答；客户端先检查能力。

设置推理为1要求AI在线；叠加可在CPU离线时独立开关。推理禁用表示停止发起新的Invoke，已在运行的Invoke可正常完成，不复位视频或加速器。叠加开关在Overlay的实际帧边界寄存器改变后才返回applied，成功应答不使用仅已同步但尚未显示生效的请求值。

500ms没有满足实际状态则返回超时，requested仍保留，稍后恢复帧同步可能继续生效。上位机应查询实际状态；必要时显式设置0取消等待意图。DEFAULTS(0x12)同时清除两个开关，并等待AI/原ISP等已应用后应答。超时后也不阻塞后续查询或关闭请求。

## 时钟与边界

UART/sys、CPU、pixel三个域独立。两个开关为独立单bit控制，各有双触发同步；不承诺两位在同一时刻变化。Overlay直接提供实际enabled状态，再双触发同步回UART。CPU允许推理信号同步到UART；APB 0x24也提供CPU域读取。CPU的ai_online必须由最终系统真实就绪条件驱动，不能为了通过协议而固定声明在线。

结果多bit数据仍通过83位稳定邮箱传输。AI域复位只重置结果接口及推理使能，不重置像素链路；已显示结果按已有超时规则隐藏。数字仿真不替代同步器放置、CDC与bundled-data物理时序约束。

`cnn_video_endpoint` 的 rgb_i/hs_i/vs_i/de_i 应接现有 ISP 输出，输出经同一拍延迟后送rgb2dvi。当前顶层尚未这样连接：需连同Sapphire/APB实际基址、共享DDR与预处理一起完成，不能将模块测试视为已上板。

## 上位机

`SerialClient.get_cnn()` 查询，`set_cnn(inference=True, overlay=False)` 可独立设置。旧固件不会收到新命令；响应的ABI、保留位和实际状态均校验。设备超时以 CnnError.status 同时保留requested与applied。保持串口原有锁和单请求/应答流程，无自动重试。GUI按钮尚未增加，不提前给旧板卡提供虚假功能。

## 验证

- `tools/run_cnn_uart_endpoint_sim.py`：物理8N1串口、真实端点/Overlay、10/14/22ns三时钟，检查独立开关、真实帧边界ACK、CRC/参数错误、离线推理拒绝、离线叠加、超时/取消、DEFAULTS及CPU复位时逐像素直通，PASS，零错误/警告。
- `tools/run_cnn_result_apb_sim.py`：原子结果接口/邮箱及官方RISC-V发布函数编译PASS。
- `tools/run_cnn_overlay_sim.py`：原1728像素标记/过期回归PASS；新增状态输出未在旧测试连接产生4条端口警告，功能断言均通过。
- `tools/run_uart_sim.py`：原串口/阈值/按键/ISP回归PASS；旧测试未连接可选端口产生23条警告。
- `tools/run_geometry_uart_sim.py`：123个Python编码数据包、真实DDR reader配置确认PASS。此前固定DATA6=0且把Gaussian bit3视为非法的预期已过时，旧HEAD同样在包0失败；更新为现有DATA6=15、非法保留bit7后通过。没有降低错误检测或改变RTL去迎合旧预期。
- `python -m unittest host.test_cnn host.test_host host.test_advanced_isp host.test_camera_controls`：29项通过。

两项旧串口runner输出移到忽略的artifacts目录，避免仿真覆盖仓库内历史work库。本轮未更改原始fpga-w.-codex，副本outflow用户改动保留。
