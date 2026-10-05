# 视频、CPU与TinyML共享DDR事务层

阶段6实现中。`cnn_shared_ddr.v`把已验证的事务缓冲、地址窗口和三路仲裁连接起来。端口0为原视频物理地址，不平移；端口1/2分别为CPU/TinyML逻辑地址，经过完整事务缓冲后转换到物理64–128MiB。全部工作于DDR用户96MHz时钟，不能跨域直连。

## 为什么先缓冲后仲裁

`cnn_axi_transaction_buffer`一次保存一个完整事务，使用256×144位同步读存储，读写复用同一数组。写请求在AWLEN+1拍全部收齐前不进入DDR；错误WLAST在本地SLVERR，不提交半个突发。读请求发出前已预留全部256拍容量，下游读响应不依赖CPU/TinyML的RREADY。合法DDR必须遵守LEN/RLAST协议；模块不是故障DDR控制器的恢复器。

RAM无复位清零，控制状态保证不读未写项。逐拍发送使用同步预取，因此写出/上游读出有拍间间隔；不能将理论128位总线峰值当实测带宽。BRAM推断、占用、时序和15FPS仍需Efinity/板上验证。

## 独立AI复位

rst_n必须是共享内存域的全局复位，不可接CPU独立复位。ai_abort[0/1]是同域的AI停止/复位意图：

- 尚在收集写数据时，取消本地事务，不访问DDR。
- 地址VALID已提出后不能违反AXI协议撤回；保持地址稳定并完成事务。
- 已发出的写从缓存继续送完，B响应独立接收；已发出的读继续收齐。丢弃旧响应，不依赖已复位的AI参与。
- ai_quiescent表示缓存端口回到空闲。顶层复位控制须保持abort直至排空，并在安全时释放新AI请求。

`cnn_axi_isolated_port`把缓冲器接到窗口，两者共用全局内存复位。因此abort不会清掉正在访问DDR的窗口状态。

## 仲裁与ID

`cnn_ddr_arbiter`一次只向DDR提交一个事务；完成后轮询下一路。持续请求的视频最多排在另外两路各一个完整事务之后，实际时长仍依赖突发长度、内部预取和DDR服务时间。不能据此跳过原视频FIFO水位、720p持续读写压力测试。

DDR ID为端口编号（4位），WID与地址ID一致；保存原8位请求ID并将其还原到CPU/TinyML响应，避免静默截断。由于只有一个在途事务，不使用DDR返回ID路由。响应错误、WSTRB、数据和LAST不丢弃。AI必须经过完整缓冲，禁止把未缓冲的CPU直接接入仲裁器后声称无反压。

## 验证

- `run_cnn_axi_transaction_buffer_sim.py`：最大256拍读写、数据/字节使能/ID/错误响应保存、上游/下游停顿、未发出取消、VALID已提出后abort、读写排空、异常WLAST、恢复，PASS。
- `run_cnn_axi_isolated_port_sim.py`：同样压力经过真实窗口，并检查非法地址本地DECERR无DDR访问，PASS。
- `run_cnn_ddr_arbiter_sim.py`：三路持续请求12个混合读写事务，轮询顺序、独占路由、原ID还原、停顿与复位，PASS。
- `run_cnn_shared_ddr_sim.py`：完整缓冲/窗口/仲裁组合。视频持续读；CPU慢速提交256拍且DDR写第一拍后abort；TinyML8拍读完整接收但上游长期不ready。全部DDR事务完成，CPU旧响应丢弃，视频完成347次读取后TinyML数据仍可正确取出，PASS。

以上测试均零错误/警告。组合测试初版在negedge采样ready与DDR驱动竞争而超时，改为在posedge采样实际握手后通过；没有改RTL以掩盖失败。

## 尚未完成

该事务层还未接入example_top/Sapphire顶层；TinyML完整AXI需转换到合并地址接口，官方转换器写响应固定OKAY，需要保留DECERR/SLVERR的适配。下一步连接真实两主设备与原视频DDR端口、顶层AI复位排空、IP依赖/SDC，进行Efinity综合、BRAM/时序及720p压力验证，再连接RAW8输入与推理软件。不得称为已上板或FPS达标。
