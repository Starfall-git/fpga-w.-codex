`timescale 1ns/1ps

/*
////--------------------2026-09-17-V0.1:既有接口裁剪整理------------------------------
1. 记录此前已删除的 MIPI CSI/DSI 与 LVDS 显示接口及其相关时钟、复位逻辑；保留 DVP 摄像头、DDR3 和 HDMI 主链路。
2. 记录原工程曾将顶层裁剪及 DDR 帧长度改为 1920x1080，而 OV5640 配置和 HDMI 时序仍为 1280x720。

////--------------------2026-09-17-V0.2:摄像头时钟与720p基线修复------------------------------
3. 恢复摄像头 XCLK 所需的独立 cam_pll 控制与锁定依赖；外围配置恢复 C12 摄像头时钟引脚。
4. 顶层裁剪尺寸和 DDR 帧长度恢复为与 OV5640、HDMI 一致的 1280x720。
5. 增加 DEBUG_LEDS 调试映射，显示 PLL 锁定、DDR 校准及 I2C 配置进度。
6. 增加默认关闭的 HDMI_TEST_PATTERN 纯色测试开关，便于隔离显示链路。
7. 同步更新 Ti60_Demo.peri.xml 的摄像头 PLL/引脚配置和 Ti60_Demo.pt.sdc 的时钟约束。
////--------------------2026-09-17-V0.2:摄像头时钟与720p基线修复------------------------------

////--------------------2026-09-18-V0.3:DDR读出后接入Sobel边缘检测------------------------------
8. 新增 src/isp/video_processing.v，统一 RGB888/HS/VS/DE 流接口并提供原图旁路。
9. 新增 src/isp/video_window3x3.v 和 video_sobel.v，实现双行缓存、3x3 梯度、阈值/灰度边缘输出。
10. 在 lcd_driver 输出之后、rgb2dvi 输入之前串联处理模块；HDMI 同步信号改接处理后的信号。
11. 新增 ENABLE_SOBEL、SOBEL_THRESHOLD、SOBEL_BINARY 参数，默认输出二值边缘。
12. 在 Ti60_Demo.xml 中登记三个新模块；补充仿真和 docs/IMAGE_PROCESSING_GUIDE.md 接口说明。
////--------------------2026-09-18-V0.3:DDR读出后接入Sobel边缘检测------------------------------

////--------------------2026-09-21-V0.4:串口上位机与运行时阈值控制------------------------------
13. 保留阈值输入端口和双键加减，按键改为双级同步、双向消抖；key_data改为打包向量。
14. 新增115200/8N1 UART收发及带序号/CRC8的命令应答协议，支持阈值设置和回读。
15. 阈值通过跨时钟邮箱从clk_sys送到clk_pixel，并在场消隐应用；确认后返回成功。
16. 顶层原阈值/按键always块保留在注释中，以uart_image_control统一仲裁替代。
17. 新增Python GUI和独立串口接口，翻转/裁剪/缩放预留协议与面板，当前RTL返回未实现。
18. 更新动态阈值仿真接口，新增UART/CDC/按键和Python协议测试及操作文档。
////--------------------2026-09-21-V0.4:串口上位机与运行时阈值控制------------------------------
*/

/*
////--------------------2026-09-22-V0.5:DDR读出几何变换与上位机实时控制------------------------------
19. 新增axi_transform_reader和迭代除法器：按源行读DDR，行缓存实现裁剪、双向翻转和最近邻缩放。
20. 新增98位几何配置邮箱及帧边界确认，保留原四帧写入/读帧所有权管理。
21. 固定1280x720输出，变换结果居中、补黑或中心截取；AXI突发不跨4KB，欠载整行补黑并报告。
22. UART实现20翻转/21裁剪/22缩放，新增02分页回读实际配置与错误标志。
23. Python GUI开放水平/垂直翻转、裁剪、倍率调节，增加已确认配置回读和恢复原图几何设置。
24. 新增DDR几何像素参考、AXI背压/跨页/帧切换测试及串口、GUI回归；帧冻结/回放/对比未纳入。
////--------------------2026-09-22-V0.5:DDR读出几何变换与上位机实时控制------------------------------
*/

/*
////--------------------2026-09-23-V0.6:快捷交互与运行时图像模式------------------------------
25. ENABLE_SOBEL和BINARY_OUTPUT改为像素域输入，默认原图、正常黑白；原图旁路对齐六拍。
26. 扩展缩放至10%-500%，GUI保留预置并支持百分比输入回车；翻转点击直接提交。
27. 新增11模式命令和12默认命令，统一恢复全部功能默认但保留阈值；应答携带实际模式。
28. 移除阈值确认/查询按钮，回车提交；交互请求合并排队，缩短串口读取及UI等待。
29. 增加模式/反相/默认保阈值/扩大缩放范围和延迟回归，更新使用说明。
////--------------------2026-09-23-V0.6:快捷交互与运行时图像模式------------------------------
*/
/*
////--------------------2026-09-23-V0.7:AR0135摄像头适配与灰度采集------------------------------
30. 替换OV5640初始化为AR0135的16位地址/16位数据I2C，读取型号、逐字节ACK检查、失败重试及真实复位/PLL等待。
31. 摄像头XCLK由16MHz改为27MHz，匹配74.25MHz传感器PLL；CTL1改为高阻输入，保留触发/OE低电平。
32. 新增AR0135 RAW8转RGB565采集，过滤AE必需的前两行元数据及尾部统计行，完整帧开始后才写入DDR。
33. DDR写入宽度由8位改为16位，仍为1280x720 RGB565；保留几何变换、Sobel、UART协议及默认设置行为。
34. 新增摄像头I2C/采集仿真和配置检查，更新摄像头适配说明；原图为AR0135灰度画面。
35. 新增Ti60_AR0135.xml及同名外围/SDC独立工程入口，避免旧Efinity窗口回写文件列表，并确保引脚配置随新工程加载。
////--------------------2026-09-23-V0.7:AR0135摄像头适配与灰度采集------------------------------
*/
/*
////--------------------2026-09-23-V0.8:修复增强边缘处理链与HDMI同步------------------------------
36. 恢复video_processing中缺失的灰度3x3窗口实例，消除window数据及HS/VS/DE无驱动导致的显示失效。
37. 保留新增NMS、双阈值、局部连接和孤立点过滤；原图旁路由6拍扩为15拍，与增强处理链同步对齐。
38. 恢复BINARY_OUTPUT运行时反相输入，独立保留GRAYSCALE_OUTPUT诊断参数，并传递IMAGE_WIDTH。
39. 新增增强算法独立像素参考和同步/旁路/模式切换回归，完整编译并核对实际外围与bit输出。
40. 通用窗口改为同步块RAM读写并打包有效位，避免三组行缓存映射为大量逻辑；总流水线延迟15拍。
////--------------------2026-09-23-V0.8:修复增强边缘处理链与HDMI同步------------------------------
*/
//`include "ddr3_controller.vh"


/* V0.2：新增两个调试参数；默认值保持摄像头图像输出。 */
module example_top #(
    parameter DEBUG_LEDS = 1,
    parameter HDMI_TEST_PATTERN = 0,
    /* V0.3 / 11：新增 Sobel 开关及阈值；ENABLE_SOBEL=0 恢复原图。
       SOBEL_BINARY=0 输出饱和灰度梯度，=1 输出黑底白边。 */
    /* V0.6 / 25: old parameter ENABLE_SOBEL=1 removed; runtime signal defaults to0. */
    /* V0.4 / 13：用户已将阈值参数改为输入变量，现由UART/按键控制，复位值128。
       原 parameter [11:0] SOBEL_THRESHOLD = 12'd128, */
    /* V0.6 / 25: old parameter SOBEL_BINARY=1 replaced by BINARY_OUTPUT input. */
    /* V0.4 / 14：与Python上位机默认波特率一致。 */
    parameter UART_BAUD = 115200
)
(
	////////////////////////////////////////////////////////////////
	//	External Clock & Reset
	//input 			nrst, 			//	Button K2
	input 			clk_24m,			//	24MHz Crystal
	input 			clk_25m,			//	25MHz Crystal 
    /* V0.4 / 13：原 input wire key_data[1:0] 为非打包数组；改为2-bit向量。 */
    input wire [1:0] key_data,
	
	////////////////////////////////////////////////////////////////
	//	System Clock
	output 			sys_pll_rstn_o, 		
	
	input 			clk_sys,			//	Sys PLL 96MHz 
	input 			clk_pixel,			//	Sys PLL 74.25MHz
	input 			clk_pixel_2x,		//	Sys PLL 148.5MHz
	input 			clk_pixel_10x,		//	Sys PLL 742.5MHz
	
	input 			sys_pll_lock,		//	Sys PLL Lock

    /* V0.2：原 LVDS PLL 同时提供摄像头 XCLK；现用独立 cam_pll 保留该时钟。 */
    output cam_pll_rstn_o,
    input  cam_pll_lock,

	
/* V0.1：此前删除 MIPI-DSI PLL 端口及相关时钟。
	////////////////////////////////////////////////////////////////
	//	MIPI-DSI Clock & Reset
	output 			dsi_pll_rstn_o,
	
	input 			dsi_refclk_i,		//	48MHz Reference Clock (for DSI PLL)
	input 			dsi_byteclk_i,		//	DSI Byte Clock (1X)
	input 			dsi_serclk_i,		//	DSI Serial Clock (4X 45)
	input 			dsi_txcclk_i,		//	DSI Serial Clock (4X 135)
	
	input 			dsi_pll_lock,
*/	

	////////////////////////////////////////////////////////////////
	//	DDR Clock
	output 			ddr_pll_rstn_o, 
	
	input 			tdqss_clk,			
	input 			core_clk,			//	DDR PLL 200MHz
	input 			tac_clk,			
	input 			twd_clk,			
	
	input 			ddr_pll_lock,		//	DDR PLL Lock
	
	////////////////////////////////////////////////////////////////
	//	DDR PLL Phase Shift Interface
	output 	[2:0] 	shift,
	output 	[4:0] 	shift_sel,
	output 			shift_ena,
	
	
/* V0.1：此前删除 LVDS 输出时钟端口；摄像头所需时钟在 V0.2 独立恢复。
	////////////////////////////////////////////////////////////////
	//	LVDS Clock
	output 			lvds_pll_rstn_o, 
	
	input 			clk_lvds_1x, 
	input 			clk_lvds_7x, 
	input 			clk_27m, 			//	RGB 1X Clock (16MHz)
	input 			clk_54m, 			//	RGB 2X Clock (32MHz, for export control)
	
	input 			lvds_pll_lock, 
*/	
	
	
	////////////////////////////////////////////////////////////////
	//	DDR Interface Ports
	output 	[15:0] 	addr,
	output 	[2:0] 	ba,
	output 			we,
	output 			reset,
	output 			ras,
	output 			cas,
	output 			odt,
	output 			cke,
	output 			cs,
	
	//	DQ I/O
	input 	[15:0] 	i_dq_hi,
	input 	[15:0] 	i_dq_lo,
	
	output 	[15:0] 	o_dq_hi,
	output 	[15:0] 	o_dq_lo,
	output 	[15:0] 	o_dq_oe,
	
	//	DM O
	output 	[1:0] 	o_dm_hi,
	output 	[1:0] 	o_dm_lo,
	
	//	DQS I/O
	input 	[1:0] 	i_dqs_hi,
	input 	[1:0] 	i_dqs_lo,
	
	input 	[1:0] 	i_dqs_n_hi,
	input 	[1:0] 	i_dqs_n_lo,
	
	output 	[1:0] 	o_dqs_hi,
	output 	[1:0] 	o_dqs_lo,
	
	output 	[1:0] 	o_dqs_n_hi,
	output 	[1:0] 	o_dqs_n_lo,
	
	output 	[1:0] 	o_dqs_oe,
	output 	[1:0] 	o_dqs_n_oe,
	
	//	CK
	output 			clk_p_hi, 
	output 			clk_p_lo, 
	output 			clk_n_hi, 
	output 			clk_n_lo, 
	
	
/*🛠️	
	////////////////////////////////////////////////////////////////
	//	MIPI-CSI Ctl / I2C
	output 			csi_ctl0_o,
	output 			csi_ctl0_oe,
	input 			csi_ctl0_i,
	
	output 			csi_ctl1_o,
	output 			csi_ctl1_oe,
	input 			csi_ctl1_i,
	
	output 			csi_scl_o,
	output 			csi_scl_oe,
	input 			csi_scl_i,
	
	output 			csi_sda_o,
	output 			csi_sda_oe,
	input 			csi_sda_i,
	
	//	MIPI-CSI RXC 
	input 			csi_rxc_lp_p_i,
	input 			csi_rxc_lp_n_i,
	output 			csi_rxc_hs_en_o,
	output 			csi_rxc_hs_term_en_o,
	input 			csi_rxc_i,
	
	//	MIPI-CSI RXD0
	output 			csi_rxd0_rst_o,
	output 			csi_rxd0_hs_en_o,
	output 			csi_rxd0_hs_term_en_o,
	
	input 			csi_rxd0_lp_p_i,
	input 			csi_rxd0_lp_n_i,
	input 	[7:0] 	csi_rxd0_hs_i,
	
	//	MIPI-CSI RXD1
	output 			csi_rxd1_rst_o,
	output 			csi_rxd1_hs_en_o,
	output 			csi_rxd1_hs_term_en_o,
	
	input 			csi_rxd1_lp_n_i,
	input 			csi_rxd1_lp_p_i,
	input 	[7:0] 	csi_rxd1_hs_i,
	
	//	MIPI-CSI RXD2
	output 			csi_rxd2_rst_o,
	output 			csi_rxd2_hs_en_o,
	output 			csi_rxd2_hs_term_en_o,
	
	input 			csi_rxd2_lp_p_i,
	input 			csi_rxd2_lp_n_i,
	input 	[7:0] 	csi_rxd2_hs_i,
	
	//	MIPI-CSI RXD3
	output 			csi_rxd3_rst_o,
	output 			csi_rxd3_hs_en_o,
	output 			csi_rxd3_hs_term_en_o,
	
	input 			csi_rxd3_lp_p_i,
	input 			csi_rxd3_lp_n_i,
	input 	[7:0] 	csi_rxd3_hs_i,
	
	//output 			csi_rxd0_fifo_rd_o, 
	//input 			csi_rxd0_fifo_empty_i, 
	//output 			csi_rxd1_fifo_rd_o, 
	//input 			csi_rxd1_fifo_empty_i, 
	//output 			csi_rxd2_fifo_rd_o, 
	//input 			csi_rxd2_fifo_empty_i, 
	//output 			csi_rxd3_fifo_rd_o, 
	//input 			csi_rxd3_fifo_empty_i, 
*/	
	
/*🛠️	删除MIPI
	////////////////////////////////////////////////////////////////
	//	DSI PWM & Reset Control 
	output 			dsi_pwm_o,			//	MIPI-DSI LCD PWM
	output 			dsi_resetn_o,		//	MIPI-DSI LCD Reset
	
	//	MIPI-DSI TXC / TXD
	output 			dsi_txc_rst_o,
	output 			dsi_txc_lp_p_oe,
	output 			dsi_txc_lp_p_o,
	output 			dsi_txc_lp_n_oe,
	output 			dsi_txc_lp_n_o,
	output 			dsi_txc_hs_oe,
	output 	[7:0] 	dsi_txc_hs_o,
	
	output 			dsi_txd0_rst_o,
	output 			dsi_txd0_hs_oe,
	output 	[7:0] 	dsi_txd0_hs_o,
	output 			dsi_txd0_lp_p_oe,
	output 			dsi_txd0_lp_p_o,
	output 			dsi_txd0_lp_n_oe,
	output 			dsi_txd0_lp_n_o,
	
	output 			dsi_txd1_rst_o,
	output 			dsi_txd1_lp_p_oe,
	output 			dsi_txd1_lp_p_o,
	output 			dsi_txd1_lp_n_oe,
	output 			dsi_txd1_lp_n_o,
	output 			dsi_txd1_hs_oe,
	output 	[7:0] 	dsi_txd1_hs_o,
	
	output 			dsi_txd2_rst_o,
	output 			dsi_txd2_lp_p_oe,
	output 			dsi_txd2_lp_p_o,
	output 			dsi_txd2_lp_n_oe,
	output 			dsi_txd2_lp_n_o,
	output 			dsi_txd2_hs_oe,
	output 	[7:0] 	dsi_txd2_hs_o,
	
	output 			dsi_txd3_rst_o,
	output 			dsi_txd3_lp_p_oe,
	output 			dsi_txd3_lp_p_o,
	output 			dsi_txd3_lp_n_oe,
	output 			dsi_txd3_lp_n_o,
	output 			dsi_txd3_hs_oe,
	output 	[7:0] 	dsi_txd3_hs_o,
	
	input 			dsi_txd0_lp_p_i,
	input 			dsi_txd0_lp_n_i,
	input 			dsi_txd1_lp_p_i,
	input 			dsi_txd1_lp_n_i,
	input 			dsi_txd2_lp_p_i,
	input 			dsi_txd2_lp_n_i,
	input 			dsi_txd3_lp_p_i,
	input 			dsi_txd3_lp_n_i,
*/	
	

	////////////////////////////////////////////////////////////////
	//	UART Interface
    /* V0.4 / 14：UART由UART_BAUD指定，默认115200-8-N-1。 */
	input 		 	uart_rx_i,
	output 		 	uart_tx_o, 
	
	
	output 	[5:0] 	led_o,			//	
	
	
	////////////////////////////////////////////////////////////////
	//	CMOS Sensor
	output 			cmos_sclk,
	input 			cmos_sdat_IN,
	output 			cmos_sdat_OUT,
	output 			cmos_sdat_OE,
	
	//	CMOS Interface
	input 			cmos_pclk,
	input 			cmos_vsync,
	input 			cmos_href,
	input 	[7:0] 	cmos_data,
	
	output 			cmos_ctl1_o, 
	output 			cmos_ctl1_oe, 
	input 			cmos_ctl1_i,
	output 			cmos_ctl2_o,
	output 			cmos_ctl2_oe, 
	input 			cmos_ctl2_i, 
	output 			cmos_ctl3_o,
	output 			cmos_ctl3_oe, 
	input 			cmos_ctl3_i, 
	
	
	////////////////////////////////////////////////////////////////
	//	HDMI Interface
	output 			hdmi_txc_oe,
	output 			hdmi_txd0_oe,
	output 			hdmi_txd1_oe,
	output 			hdmi_txd2_oe,
	
	output 			hdmi_txc_rst_o,
	output 			hdmi_txd0_rst_o,
	output 			hdmi_txd1_rst_o,
	output 			hdmi_txd2_rst_o,
	
	output 	[9:0] 	hdmi_txc_o,
	output 	[9:0] 	hdmi_txd0_o,
	output 	[9:0] 	hdmi_txd1_o,
	output 	[9:0] 	hdmi_txd2_o,
	
/*🛠️	删除MIPI_LVDS	
	////////////////////////////////////////////////////////////////
	//	LVDS Interface
	output 			lvds_txc_oe,
	output 	[6:0] 	lvds_txc_o,
	output 			lvds_txc_rst_o,
	
	output 			lvds_txd0_oe,
	output 	[6:0] 	lvds_txd0_o,
	output 			lvds_txd0_rst_o,
	
	output 			lvds_txd1_oe,
	output 	[6:0] 	lvds_txd1_o,
	output 			lvds_txd1_rst_o,
	
	output 			lvds_txd2_oe,
	output 	[6:0] 	lvds_txd2_o,
	output 			lvds_txd2_rst_o,
	
	output 			lvds_txd3_oe,
	output 	[6:0] 	lvds_txd3_o,
	output 			lvds_txd3_rst_o,
*/	
	
	////////////////////////////////////////////////////////////////
	//	RGB LCD 5Inch 800x480
	output 			lcd_tp_sda_o,		//	TP SDA
	output 			lcd_tp_sda_oe,
	input 			lcd_tp_sda_i,
	
	output 			lcd_tp_scl_o,		//	TP SCL
	output 			lcd_tp_scl_oe,
	input 			lcd_tp_scl_i,
	
	output 			lcd_tp_int_o,		//	TP INT
	output 			lcd_tp_int_oe,
	input 			lcd_tp_int_i,
	
	output 			lcd_tp_rst_o,		//	TP RST
	
	output 			lcd_pwm_o,			//	Backlight
	output 			lcd_blen_o,
	
	//output 			lcd_pclk_o,			//	PCLK & SCK Mux
	output 			lcd_vs_o,			//	VS & SSN Mux. Fixed to 1. Use DE-Only mode. 
	output 			lcd_hs_o,			//	HS. Fixed to 1. Use DE-Only mode. 
	output 			lcd_de_o,			//	DE. 

	output 	[7:0] 	lcd_b7_0_o,			//	B7:B0. 
	output 	[7:0] 	lcd_g7_0_o,			//	G7:G0. Must output 8'hFF when access SPI. 
	output 	[7:0] 	lcd_r7_0_o,			//	R7:R0. 
	
	output 	[7:0] 	lcd_b7_0_oe,		//	B7:B0. 
	output 	[7:0] 	lcd_g7_0_oe,		//	G7:G0. Must output 8'hFF when access SPI. 
	output 	[7:0] 	lcd_r7_0_oe,		//	R7:R0. 

	input 	[7:0] 	lcd_b7_0_i,			//	B7:B0. 
	input 	[7:0] 	lcd_g7_0_i,			//	G7:G0. Must output 8'hFF when access SPI. 
	input 	[7:0] 	lcd_r7_0_i,			//	R7:R0. 
	
	//	SPI Pins
	output 			spi_sck_o, 
	output 			spi_ssn_o 			
);
	
/*🛠️	删除MIPI_LVDS    
	wire 			csi_rxd0_fifo_rd_o; 
	wire 			csi_rxd0_fifo_empty_i = 0;  
	wire 			csi_rxd1_fifo_rd_o;  
	wire 			csi_rxd1_fifo_empty_i = 0;  
	wire 			csi_rxd2_fifo_rd_o;  
	wire 			csi_rxd2_fifo_empty_i = 0;  
	wire 			csi_rxd3_fifo_rd_o;  
	wire 			csi_rxd3_fifo_empty_i = 0;  
*/	
	
	parameter 	SIM_DATA 	= 0; 
	
	//	Hardware Configuration
	assign clk_p_hi = 1'b0;	//	DDR3 Clock requires 180 degree shifted. 
	assign clk_p_lo = 1'b1;
	assign clk_n_hi = 1'b1;
	assign clk_n_lo = 1'b0; 
	
	assign cmos_ctl1_o = 0; 
	/* V0.7 / 31: old OE=1 removed. CTL1 is AR0135 FLASH output,
       so FPGA must release this pad; CTL2=TRIGGER=0, CTL3=OE_BAR=0. */
    assign cmos_ctl1_oe = 0;
	assign cmos_ctl2_o = 0; 
	assign cmos_ctl2_oe = 1; 
	assign cmos_ctl3_o = 0; 
	assign cmos_ctl3_oe = 1; 
	
	//	System Clock Tree Control
	assign sys_pll_rstn_o = 1'b1; 	//	nrst; 	//	Reset whole system when nrst (K2) is pressed. 
	
//🛠️	删除MIPI_LVDS    
//	assign dsi_pll_rstn_o = sys_pll_lock; 
	assign ddr_pll_rstn_o = sys_pll_lock;
    /* V0.2：系统 PLL 锁定后释放摄像头 PLL 复位。 */
    assign cam_pll_rstn_o = sys_pll_lock; 
//	assign lvds_pll_rstn_o = sys_pll_lock; 
 
//  🛠️删除dsi复位信号
//	wire 			w_pll_lock = sys_pll_lock && dsi_pll_lock && ddr_pll_lock && lvds_pll_lock; 
    /* V0.2：加入摄像头 PLL 锁定条件，避免其时钟未稳定就释放系统复位。 */
	wire 			w_pll_lock = sys_pll_lock && ddr_pll_lock && cam_pll_lock; 
	
	//	Synchronize System Resets. 
	reg 			rstn_sys = 0, rstn_pixel = 0; 
	wire 			rst_sys = ~rstn_sys, rst_pixel = ~rstn_pixel; 
	
//🛠️	删除MIPI_LVDS
//	reg 			rstn_dsi_refclk = 0, rstn_dsi_byteclk = 0; 
//	wire 			rst_dsi_refclk = ~rstn_dsi_refclk, rst_dsi_byteclk = ~rstn_dsi_byteclk; 
	
//	reg 			rstn_lvds_1x = 0; 
//	wire 			rst_lvds_1x = ~rstn_lvds_1x; 
	
//	reg 			rstn_27m = 0, rstn_54m = 0; 
//	wire 			rst_27m = ~rstn_27m, rst_54m = ~rstn_54m; 
	
	//	Clock Gen
//	always @(posedge clk_27m or negedge w_pll_lock) begin if(~w_pll_lock) rstn_27m <= 0; else rstn_27m <= 1; end
//	always @(posedge clk_54m or negedge w_pll_lock) begin if(~w_pll_lock) rstn_54m <= 0; else rstn_54m <= 1; end
	always @(posedge clk_sys or negedge w_pll_lock) begin if(~w_pll_lock) rstn_sys <= 0; else rstn_sys <= 1; end
	always @(posedge clk_pixel or negedge w_pll_lock) begin if(~w_pll_lock) rstn_pixel <= 0; else rstn_pixel <= 1; end
    
//🛠️	删除MIPI
//	always @(posedge dsi_refclk_i or negedge w_pll_lock) begin if(~w_pll_lock) rstn_dsi_refclk <= 0; else rstn_dsi_refclk <= 1; end
//	always @(posedge dsi_byteclk_i or negedge w_pll_lock) begin if(~w_pll_lock) rstn_dsi_byteclk <= 0; else rstn_dsi_byteclk <= 1; end
//	always @(posedge clk_lvds_1x or negedge w_pll_lock) begin if(~w_pll_lock) rstn_lvds_1x <= 0; else rstn_lvds_1x <= 1; end
	
	
	localparam 	CLOCK_MAIN 	= 96000000; 	//	System clock using 96MHz. 
	
	
	
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	//	Flash Burner Control
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	wire 			w_ustick, w_mstick; 
	
	wire  [7:0] 	w_dev_index_o;  
	wire  [7:0] 	w_dev_cmd_o;  
	wire  [31:0] 	w_dev_wdata_o;  
	wire  		w_dev_wvalid_o;  
	wire  		w_dev_rvalid_o;  
	wire 	[31:0] 	w_dev_rdata_i;  
	
	wire 			w_spi_ssn_o, w_spi_sck_o; 
	wire 	[3:0] 	w_spi_data_o, w_spi_data_oe; 
	wire 	[3:0] 	w_spi_data_i; 
	
	//	Flash Control
	reg 			r_flash_en = 0; 		//	0x00:0x00 Enable Flash
	
	always @(posedge clk_sys) begin
		r_flash_en <= (w_dev_wvalid_o && (w_dev_index_o == 8'h00) && (w_dev_cmd_o == 8'h00)) ? w_dev_wdata_o : r_flash_en; 
	end
	
	
	
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	//	LCD Data Mux
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	wire 	[7:0] 	w_lcd_b_o, w_lcd_g_o, w_lcd_r_o; 
	
	assign lcd_b7_0_o = r_flash_en ? {4'b0, w_spi_data_o[3:2], 2'b0} : w_lcd_b_o; 
	assign lcd_g7_0_o = r_flash_en ? {6'h0, w_spi_data_o[1:0]} : w_lcd_g_o; 
	assign lcd_r7_0_o = r_flash_en ? {8'h00} : w_lcd_r_o; 
	
	assign lcd_b7_0_oe = r_flash_en ? {4'b0, w_spi_data_oe[3:2], 2'b0} : 8'hFF; 
	assign lcd_g7_0_oe = r_flash_en ? {6'h0, w_spi_data_oe[1:0]} : 8'hFF; 
	assign lcd_r7_0_oe = r_flash_en ? {8'h00} : 8'hFF; 
	
	assign spi_sck_o = w_spi_sck_o; 
	assign spi_ssn_o = w_spi_ssn_o; 
	assign w_spi_data_i = {lcd_b7_0_i[3:2], lcd_g7_0_i[1:0]}; 
	
	
	
	
	
	
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	//	DDR3 Controller
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	wire			w_ddr3_ui_clk = clk_sys;
	wire			w_ddr3_ui_rst = rst_sys;
	wire			w_ddr3_ui_areset = rst_sys;
	wire			w_ddr3_ui_aresetn = rstn_sys;
	

	//	General AXI Interface 
	wire	[3:0] 	w_ddr3_awid;
	wire	[31:0]	w_ddr3_awaddr;
	wire	[7:0]		w_ddr3_awlen;
	wire			w_ddr3_awvalid;
	wire			w_ddr3_awready;
	
	wire 	[3:0]  	w_ddr3_wid;
	wire 	[127:0] 	w_ddr3_wdata;
	wire 	[15:0]	w_ddr3_wstrb;
	wire			w_ddr3_wlast;
	wire			w_ddr3_wvalid;
	wire			w_ddr3_wready;
	
	wire 	[3:0] 	w_ddr3_bid;
	wire 	[1:0] 	w_ddr3_bresp;
	wire			w_ddr3_bvalid;
	wire			w_ddr3_bready;
	
	wire	[3:0] 	w_ddr3_arid;
	wire	[31:0]	w_ddr3_araddr;
	wire	[7:0]		w_ddr3_arlen;
	wire			w_ddr3_arvalid;
	wire			w_ddr3_arready;
	
	wire 	[3:0] 	w_ddr3_rid;
	wire 	[127:0] 	w_ddr3_rdata;
	wire			w_ddr3_rlast;
	wire			w_ddr3_rvalid;
	wire			w_ddr3_rready;
	wire 	[1:0] 	w_ddr3_rresp;
	
	
	//	AXI Interface Request
	wire 	[3:0] 	w_ddr3_aid;
	wire 	[31:0] 	w_ddr3_aaddr;
	wire 	[7:0]  	w_ddr3_alen;
	wire 	[2:0]  	w_ddr3_asize;
	wire 	[1:0]  	w_ddr3_aburst;
	wire 	[1:0]  	w_ddr3_alock;
	wire			w_ddr3_avalid;
	wire			w_ddr3_aready;
	wire			w_ddr3_atype;
	
	wire 			w_ddr3_cal_done, w_ddr3_cal_pass; 
	
	//	Do not issue DDR read / write when ~cal_done. 
	reg 			r_ddr_unlock = 0; 
	always @(posedge w_ddr3_ui_clk or negedge w_ddr3_ui_aresetn) begin
		if(~w_ddr3_ui_aresetn)
			r_ddr_unlock <= 0; 
		else
			r_ddr_unlock <= w_ddr3_cal_done; 
	end
	
	DdrCtrl ddr3_ctl_axi (	
		.core_clk		(core_clk),
		.tac_clk		(tac_clk),
		.twd_clk		(twd_clk),	
		.tdqss_clk		(tdqss_clk),
		
		.reset		(reset),
		.cs			(cs),
		.ras			(ras),
		.cas			(cas),
		.we			(we),
		.cke			(cke),    
		.addr			(addr),
		.ba			(ba),
		.odt			(odt),
		
		.o_dm_hi		(o_dm_hi),
		.o_dm_lo		(o_dm_lo),
		
		.i_dq_hi		(i_dq_hi),
		.i_dq_lo		(i_dq_lo),
		.o_dq_hi		(o_dq_hi),
		.o_dq_lo		(o_dq_lo),
		.o_dq_oe		(o_dq_oe),
		
		.i_dqs_hi		(i_dqs_hi),
		.i_dqs_lo		(i_dqs_lo),
		.i_dqs_n_hi		(i_dqs_n_hi),
		.i_dqs_n_lo		(i_dqs_n_lo),
		.o_dqs_hi		(o_dqs_hi),
		.o_dqs_lo		(o_dqs_lo),
		.o_dqs_n_hi		(o_dqs_n_hi),
		.o_dqs_n_lo		(o_dqs_n_lo),
		.o_dqs_oe		(o_dqs_oe),
		.o_dqs_n_oe		(o_dqs_n_oe),
		
		.clk			(w_ddr3_ui_clk),
		.reset_n		(w_ddr3_ui_aresetn),
		
		.axi_avalid		(w_ddr3_avalid),	//	Enable command only when unlocked. 
		.axi_aready		(w_ddr3_aready),
		.axi_aaddr		(w_ddr3_aaddr),
		.axi_aid		(w_ddr3_aid),
		.axi_alen		(w_ddr3_alen),
		.axi_asize		(w_ddr3_asize),
		.axi_aburst		(w_ddr3_aburst),
		.axi_alock		(w_ddr3_alock),
		.axi_atype		(w_ddr3_atype),
		
		.axi_wid		(w_ddr3_wid),
		.axi_wvalid		(w_ddr3_wvalid),
		.axi_wready		(w_ddr3_wready),
		.axi_wdata		(w_ddr3_wdata),
		.axi_wstrb		(w_ddr3_wstrb),
		.axi_wlast		(w_ddr3_wlast),
		
		.axi_bvalid		(w_ddr3_bvalid),
		.axi_bready		(w_ddr3_bready),
		.axi_bid		(w_ddr3_bid),
		.axi_bresp		(w_ddr3_bresp),
		
		.axi_rvalid		(w_ddr3_rvalid),
		.axi_rready		(w_ddr3_rready),
		.axi_rdata		(w_ddr3_rdata),
		.axi_rid		(w_ddr3_rid),
		.axi_rresp		(w_ddr3_rresp),
		.axi_rlast		(w_ddr3_rlast),
		
		.shift		(shift),
		.shift_sel		(),
		.shift_ena		(shift_ena),
		
		.cal_ena		(1'b1),
		.cal_done		(w_ddr3_cal_done),
		.cal_pass		(w_ddr3_cal_pass)
	);
	
	assign w_ddr3_bready = 1'b1; 
	assign shift_sel = 5'b00100; 		//	ddr_tac_clk always use PLLOUT[2]. 
	
	
	AXI4_AWARMux #(.AID_LEN(4), .AADDR_LEN(32)) axi4_awar_mux (
		.aclk_i			(w_ddr3_ui_clk), 
		.arst_i			(w_ddr3_ui_rst), 
		
		.awid_i			(w_ddr3_awid),
		.awaddr_i			(w_ddr3_awaddr),
		.awlen_i			(w_ddr3_awlen),
		.awvalid_i			(w_ddr3_awvalid && r_ddr_unlock),
		.awready_o			(w_ddr3_awready),
		
		.arid_i			(w_ddr3_arid),
		.araddr_i			(w_ddr3_araddr),
		.arlen_i			(w_ddr3_arlen),
		.arvalid_i			(w_ddr3_arvalid && r_ddr_unlock),
		.arready_o			(w_ddr3_arready),
		
		.aid_o			(w_ddr3_aid),
		.aaddr_o			(w_ddr3_aaddr),
		.alen_o			(w_ddr3_alen),
		.atype_o			(w_ddr3_atype),
		.avalid_o			(w_ddr3_avalid),
		.aready_i			(w_ddr3_aready)
	);
	
	assign w_ddr3_asize = 4; 		//	Fixed 128 bits (16 bytes, size = 4)
	assign w_ddr3_aburst = 1; 
	assign w_ddr3_alock = 0; 
	
	//assign led_o[1:0] = {w_ddr3_cal_pass, w_ddr3_cal_done}; 
	
	
	
	
	
	
	
	////////////////////////////////////////////////////////////////
    /* V0.7 / 30: replaced OV5640 controller/LUT (wire address78,
       16-bit register + 8-bit data) with AR0135 (20/21, 16+16).
       Prior implementation is backed up in tools/debug/before-v07/example_top.v. */
    wire camera_config_done, camera_config_error;
    wire [15:0] camera_model_id;
    wire [7:0] camera_config_index;
    ar0135_init #(.CLK_FREQ(CLOCK_MAIN), .I2C_FREQ(100000)) u_camera_init (
        .clk(clk_sys), .rst_n(rstn_sys),
        .scl(cmos_sclk), .sda_o(cmos_sdat_OUT),
        .sda_oe(cmos_sdat_OE), .sda_i(cmos_sdat_IN),
        .done(camera_config_done), .error(camera_config_error),
        .model_id(camera_model_id), .config_index(camera_config_index)
    );
    /* Hardware connector: cmos_data[7:0] = AR0135 DOUT[11:4].
       CTRL0/RESET_BAR has module RC pull-up, not an FPGA port on this board. */

	//input 			cmos_pclk,
	//input 			cmos_vsync,
	//input 			cmos_href,
	//input 	[7:0] 	cmos_data,
	
	wire 			w_cmos_pclk = cmos_pclk; 
	
	
	
	//	Output LED
	reg 	[3:0]		r_cmos_fv_o = 0; 
	reg 	[1:0] 	r_cmos_rx_vsync0_in = 0; 
	always @(posedge w_cmos_pclk) begin
		r_cmos_rx_vsync0_in <= {r_cmos_rx_vsync0_in, cmos_vsync}; 
		r_cmos_fv_o <= r_cmos_fv_o + ((r_cmos_rx_vsync0_in == 2'b01) ? 1 : 0); 
	end
	assign led_o[5] = r_cmos_fv_o[3]; 
	
	
	
	
	
	
	
	
	////////////////////////////////////////////////////////////////
	//	System Control. Can be removed for public. 
	
	localparam 	CLK_FREQ 	= 96_000_000; 	//	clk_sys is 96MHz. 
	localparam 	BAUD_RATE 	= 460_800; 		//	Use 460800-8-N-1. 
	
	
	//	SFR I/O Interface
	wire 	[7:0] 	w_sfr_addr_o; 	//	SFR Address (0xFF00 ~ 0xFFFF). 00:Power; 40~5F:Stream0; 60~7F:Stream1. 
	wire 	[7:0] 	w_sfr_wdata_o; 	//	SFR Write Data. 
	wire 			w_sfr_we_o; 		//	SFR WE. 
	reg 	[7:0] 	w_sfr_rdata_i; 	//	Must be valid after sfr_rd_o. 
	wire 			w_sfr_rd_o; 		//	SFR RD. 
	
/*🛠️	删除MIPI	
	//	System Control Registers
	reg 			r_dsi_tx_rstn = 0; 	//	DSI TX Reset
	reg 	[7:0] 	r_dsi_pwm = 64; 		//	[6:0]PWM, [7]Pol
	reg 			r_dsi_resetn_o = 0; 	//	DSI Panel Reset
	reg 			r_dsi_data_rstn = 0; 	//	DSI TX Reset
	
	reg 	[3:0] 	r_dsi_lp_p_ovr = 0; 	
	reg 	[3:0] 	r_dsi_lp_n_ovr = 0; 	
*/	
	
	
	//	AXI-Lite Interface Bridge
	localparam 	CSI_AXILITE_ID 	= 0; 				//	Select DSI_TX when r_axi_sel = DSI_AXILITE_ID. 
	localparam 	DSI_AXILITE_ID 	= 1; 				//	Select DSI_TX when r_axi_sel = DSI_AXILITE_ID. 
	
	reg 	[7:0] 	r_axi_addr = 8'h18; 		//	0xE0 (RW)
	reg 	[31:0] 	r_axi_wdata = 32'h0000000A; 	//	0xE1~0xE4 (RW)
	wire 	[31:0] 	w_axi_rdata; 			//	0xE5~0xE8 (RO)
	reg 	[0:0] 	r_axi_sel = 1; 			//	0xE9[7:2] (RW)
	reg 			r_axi_r1w0 = 0; 			//	0xE9[1] (RW)
	reg 			r_axi_req = 0; 			//	0xE9[0] (WO, Single Cycle)
	reg 			r_axi_req_o = 0; 			//	Delayed of r_axi_req. 
	
	
	//	Buffered AXI Read Data
	reg 	[31:0] 	r_axi_rdata = 0; 		//	Use state machine
	reg 			r_axi_idle = 0; 		//	AXI Idle 
	
	reg 	[3:0] 	rs_axilite = 0; 		//	AXI Access
	wire 	[3:0] 	ws_axilite_idle = 0; 		
	wire 	[3:0] 	ws_axilite_write = 1; 
	wire 	[3:0] 	ws_axilite_read = 2; 
	wire 	[3:0] 	ws_axilite_endread = 3; 
	
	reg 			r_axi_awvalid = 0, r_axi_wvalid = 0, r_axi_arvalid = 0; 
	wire 			w_axi_awready, w_axi_wready, w_axi_arready, w_axi_rvalid; 
	
	
	reg 	[3:0] 	rc_axi_init = 0; 

	always @(posedge clk_sys or posedge rst_sys) begin
		if(rst_sys) begin
//🛠️	删除MIPI        
//			r_dsi_tx_rstn <= 0; 
//			r_dsi_pwm <= 64; 
			r_axi_req <= 0; 
//			r_dsi_resetn_o <= 0; 
//			r_dsi_data_rstn <= 0; 
			
			rs_axilite <= 0; 
			r_axi_awvalid <= 0; 
			r_axi_wvalid <= 0;
			r_axi_arvalid <= 0; 
			
//			r_dsi_lp_p_ovr <= 0; 
//			r_dsi_lp_n_ovr <= 0; 
			
			rc_axi_init <= 0; 
			r_axi_idle <= 0; 
			
		end else begin
//			r_dsi_tx_rstn <= 1; 
//			r_dsi_resetn_o <= 1; 
//			r_dsi_data_rstn <= 1; 
			
		end
	end
	
//	assign dsi_resetn_o = r_dsi_resetn_o; 
	
//	assign csi_ctl0_oe = 0; 
//	assign csi_ctl1_oe = 0; 
	
/*🛠️	删除MIPI_LVDS	
	PWMLite dsi_pwm (		//	#(.ENABLE_TICK(0), .PWM_BITS(7)) 
		.clk_i			(clk_sys),
		.rst_i			(rst_sys),
		.pwm_i			(r_dsi_pwm[6:0]),
		.pol_i			(r_dsi_pwm[7]), 
		.pwm_o			(dsi_pwm_o)
	);
*/



//🛠️	调试MIPI
	////////////////////////////////////////////////////////////////
	//	MIPI CSI RX
	
    /* V0.7 / 32-33: removed the OV5640 byte-stream crop and 64-bit
       temporary wires. AR0135 has ONE gray sample per PCLK, not two RGB bytes.
       Convert before DDR so all existing reader/ISP controls keep RGB565. */
    wire cmos_frame_vsync;
    wire cmos_frame_href;
    wire [15:0] cmos_frame_Gray;
    ar0135_capture #(.WIDTH(1280), .HEIGHT(720), .EMBEDDED_ROWS(2)) u_camera_capture (
        .pclk(w_cmos_pclk), .rst_n(rstn_sys), .configured(camera_config_done),
        .fv(cmos_vsync), .lv(cmos_href), .raw(cmos_data),
        .frame_valid(cmos_frame_vsync), .pixel_valid(cmos_frame_href),
        .rgb565(cmos_frame_Gray)
    );


	












	////////////////////////////////////////////////////////////////
	//	DDR R/W Control
	

	wire                            lcd_de;
	wire                            lcd_hs;      
	wire                            lcd_vs;
	wire 					  lcd_request; 
	wire            [7:0]           lcd_red, lcd_red2;
	wire            [7:0]           lcd_green, lcd_green2;
	wire            [7:0]           lcd_blue, lcd_blue2;
	wire            [15:0]          lcd_data;
    /* V0.5 / 20,21: control mailbox crosses to DDR reader with toggle/ack handshake. */
    wire [97:0] transform_geometry;
    wire transform_toggle, transform_ack;
    wire [1:0] transform_faults;


	assign w_ddr3_awid = 0; 
	assign w_ddr3_wid = 0; 
	
	wire 			w_wframe_vsync; 
	wire 	[7:0] 	w_axi_tp; 
	
	//	Write in 8 bits. Read in 16 bits. 
    /* V0.2：DDR 读取帧长度由 1920x1080x2 恢复为 1280x720x2 字节。 */
	axi4_ctrl #(
    /* V0.5 / 19: select line-buffer transform reader; legacy branch remains in axi4_ctrl. */
    .C_TRANSFORM(1), .IMAGE_WIDTH(1280), .IMAGE_HEIGHT(720),
    .C_RD_END_ADDR(1280 * 2 * 720), 
    .C_W_WIDTH(16) /* V0.7 / 33: was 8-bit OV5640 byte stream. */,
    .C_R_WIDTH(16), 
    .C_ID_LEN(4))
    u_axi4_ctrl (

		.axi_clk        (w_ddr3_ui_clk            ),
		.axi_reset      (w_ddr3_ui_rst            ),

		.axi_awaddr     (w_ddr3_awaddr       ),
		.axi_awlen      (w_ddr3_awlen        ),
		.axi_awvalid    (w_ddr3_awvalid      ),
		.axi_awready    (w_ddr3_awready      ),

		.axi_wdata      (w_ddr3_wdata        ),
		.axi_wstrb      (w_ddr3_wstrb        ),
		.axi_wlast      (w_ddr3_wlast        ),
		.axi_wvalid     (w_ddr3_wvalid       ),
		.axi_wready     (w_ddr3_wready       ),

		.axi_bid        (0          ),
		.axi_bresp      (0        ),
		.axi_bvalid     (1       ),

		.axi_arid       (w_ddr3_arid         ),
		.axi_araddr     (w_ddr3_araddr       ),
		.axi_arlen      (w_ddr3_arlen        ),
		.axi_arvalid    (w_ddr3_arvalid      ),
		.axi_arready    (w_ddr3_arready      ),

		.axi_rid        (w_ddr3_rid          ),
		.axi_rdata      (w_ddr3_rdata        ),
		/* V0.5 / 21: propagate actual DDR response errors to transform diagnostics. */
		.axi_rresp      (w_ddr3_rresp),
		.axi_rlast      (w_ddr3_rlast        ),
		.axi_rvalid     (w_ddr3_rvalid       ),
		.axi_rready     (w_ddr3_rready       ),

		.wframe_pclk    (w_cmos_pclk          ),
		.wframe_vsync   (cmos_frame_vsync), //w_wframe_vsync   ),		//	Writter VSync. Flush on rising edge. Connect to EOF. 
		.wframe_data_en (cmos_frame_href   ),
		.wframe_data    (cmos_frame_Gray),
		
		.rframe_pclk    (clk_pixel            ),
		.rframe_vsync   (~lcd_vs             ),		//	Reader VSync. Flush on rising edge. Connect to ~EOF. 
		.rframe_data_en (lcd_request             ),
		.rframe_data    (lcd_data           ),

        /* V0.5 / 20: complete configuration, stable until acknowledged after frame setup. */
        .geometry_i(transform_geometry), .geometry_toggle_i(transform_toggle),
        .geometry_ack_o(transform_ack), .transform_faults_o(transform_faults),
		
		.tp_o 		(w_axi_tp)
	);
    /* V0.2：LED[3:0] 显示 PLL/DDR 状态，LED[4] 显示 I2C 配置序列完成。
       DEBUG_LEDS=0 时 LED[3:0] 恢复原有 AXI 测试信号；LED[4] 仅代表序列完成，不代表 ACK 成功。 */
    assign led_o[3:0] = DEBUG_LEDS ?
        {w_ddr3_cal_pass, w_ddr3_cal_done, cam_pll_lock, sys_pll_lock} : w_axi_tp[3:0];
    /* V0.7 / 34: LED4 now means AR0135 configuration ACKed, not OV5640.
       LED5 remains FV heartbeat; failed initialization leaves LED4 low. */
    assign led_o[4] = camera_config_done;
	
	
	
	
	////////////////////////////////////////////////////////////////
	//  LCD Timing Driver
	wire 	[15:0] 	w_lcd_data_swap = {lcd_data[7:0], lcd_data[15:8]}; 
	wire 	[7:0] 	lcd_data_r = {lcd_data[15:11], 3'b0}; 
	wire 	[7:0] 	lcd_data_g = {lcd_data[10:5], 2'b0}; 
	wire 	[7:0] 	lcd_data_b = {lcd_data[4:0], 3'b0}; 
	
	lcd_driver u_lcd_driver
	(
	    //  global clock
	    .clk        (clk_pixel   ),
	    .rst_n      (rstn_pixel), 
	    
	    //  lcd interface
	    .lcd_dclk   (               ),
	    .lcd_blank  (               ),
	    .lcd_sync   (               ),
	    .lcd_request(lcd_request    ), 	//	Request data 1 cycle ahead. 
	    .lcd_hs     (lcd_hs         ),
	    .lcd_vs     (lcd_vs         ),
	    .lcd_en     (lcd_de         ),
	    .lcd_rgb    ({lcd_red2,lcd_green2,lcd_blue2, lcd_red,lcd_green,lcd_blue}),
	    
	    //  user interface
	    .lcd_data   ({lcd_data_r, lcd_data_g, lcd_data_b}  )
	);
	
	
	
	////////////////////////////////////////////////////////////////
/* V0.3 / 8~10：新增 DDR 显示数据处理链。
       lcd_driver 已把 DDR RGB565 数据转换为带时序的 RGB888 流。
       DDR 的 lcd_request 和 rframe_vsync 仍使用原始时序；
       仅送 HDMI 的 RGB/HS/VS/DE 一起经过处理模块。 */
    wire [23:0] processed_rgb;
    /* V0.4 / 13、16：原按键直接写系统域阈值，现由统一控制模块替代。
       原实现保留如下（含原寄存器及按键计数），避免同一阈值存在多个驱动：
    reg [11:0] SOBEL_THRESHOLD;
    reg [23:0] cnt1_20ms,cnt2_20ms; //计数器
    reg key_flag1,key_flag2;
    parameter CNT_MAX = 24'd1_920_000;
    always@(posedge clk_sys or negedge rstn_sys)
    if(rstn_sys == 1'b0)
        cnt1_20ms <= 24'b0;
    else if(key_data[0] == 1'b1)
        cnt1_20ms <= 24'b0;
    else if(cnt1_20ms == CNT_MAX && key_data[0] == 1'b0)
        cnt1_20ms <= cnt1_20ms;
    else
        cnt1_20ms <= cnt1_20ms + 1'b1;
      
    always@(posedge clk_sys or negedge rstn_sys)
    if(rstn_sys == 1'b0)
        cnt2_20ms <= 24'b0;
    else if(key_data[1] == 1'b1)
        cnt2_20ms <= 24'b0;
    else if(cnt2_20ms == CNT_MAX && key_data[1] == 1'b0)
        cnt2_20ms <= cnt2_20ms;
    else
        cnt2_20ms <= cnt2_20ms + 1'b1;
        
    always@(posedge clk_sys or negedge rstn_sys)
    if(rstn_sys == 1'b0)
        key_flag1 <= 1'b0;
    else if(cnt1_20ms == CNT_MAX - 1'b1)
        key_flag1 <= 1'b1;
    else
        key_flag1 <= 1'b0;
        
    always@(posedge clk_sys or negedge rstn_sys)
    if(rstn_sys == 1'b0)
        key_flag2 <= 1'b0;
    else if(cnt2_20ms == CNT_MAX - 1'b1)
        key_flag2 <= 1'b1;
    else
        key_flag2 <= 1'b0;
        
    always@(posedge clk_sys or negedge rstn_sys) begin
    if(!rstn_sys) SOBEL_THRESHOLD <= 12'd128;    
    else begin
    if(key_flag1 == 1) begin
         if(SOBEL_THRESHOLD == 12'd4095) SOBEL_THRESHOLD <=SOBEL_THRESHOLD;
         else 
        SOBEL_THRESHOLD <= SOBEL_THRESHOLD + 1'b1;
    end
    else if(key_flag2) begin
         if(SOBEL_THRESHOLD == 0) SOBEL_THRESHOLD <=SOBEL_THRESHOLD;
         else 
            SOBEL_THRESHOLD <= SOBEL_THRESHOLD - 1'b1;
    end
    end
    end
    
    
    wire processed_hs, processed_vs, processed_de;
    */
    wire [11:0] SOBEL_THRESHOLD;
    /* V0.6 / 25: applied pixel-domain mode outputs, not compile-time parameters. */
    wire ENABLE_SOBEL, BINARY_OUTPUT;
    wire processed_hs, processed_vs, processed_de;
    /* V0.4 / 14~16：UART/按键共同控制；输出阈值已经安全进入像素时钟域。
       processed_vs低有效时处于场消隐，处理流水中已没有上一帧有效像素。 */
    uart_image_control #(
        .CLOCK_HZ(CLOCK_MAIN), .BAUD(UART_BAUD),
        .DEBOUNCE_CYCLES(CLOCK_MAIN/50)
    ) u_image_control (
        .clk(clk_sys), .rst_n(rstn_sys), .uart_rx_i(uart_rx_i), .uart_tx_o(uart_tx_o),
        .key_data(key_data), .pixel_clk(clk_pixel), .pixel_rst_n(rstn_pixel),
        .frame_blank_i(!processed_vs), .threshold_pixel_o(SOBEL_THRESHOLD),
        .enable_sobel_o(ENABLE_SOBEL), .binary_output_o(BINARY_OUTPUT),
        /* V0.5 / 22: UART now controls DDR source geometry as well as Sobel threshold. */
        .geometry_o(transform_geometry), .geometry_toggle_o(transform_toggle),
        .geometry_ack_i(transform_ack), .transform_faults_i(transform_faults)
    );
    video_processing #(
        .IMAGE_WIDTH(1280),
        /* V0.6: runtime enable/polarity connect below; parameter overrides removed. */
        .VS_ACTIVE(1'b0)
    ) u_video_processing (
        .clk(clk_pixel), .rst_n(rstn_pixel),
        .SOBEL_THRESHOLD(SOBEL_THRESHOLD),
        .ENABLE_SOBEL(ENABLE_SOBEL), .BINARY_OUTPUT(BINARY_OUTPUT),
        .rgb_i({lcd_red, lcd_green, lcd_blue}),
        .hs_i(lcd_hs), .vs_i(lcd_vs), .de_i(lcd_de),
        .rgb_o(processed_rgb),
        .hs_o(processed_hs), .vs_o(processed_vs), .de_o(processed_de)
    );

    // HDMI Interface.
	
	//	HDMI requires specific timing, thus is not compatible with LCD & LVDS & DSI. Must implement standalone. 
	
	assign hdmi_txd0_rst_o = rst_pixel; 
	assign hdmi_txd1_rst_o = rst_pixel; 
	assign hdmi_txd2_rst_o = rst_pixel; 
	assign hdmi_txc_rst_o = rst_pixel; 
	
	assign hdmi_txd0_oe = 1'b1; 
	assign hdmi_txd1_oe = 1'b1; 
	assign hdmi_txd2_oe = 1'b1; 
	assign hdmi_txc_oe = 1'b1; 
	
	//-------------------------------------
	//Digilent HDMI-TX IP Modified by CB elec.
	rgb2dvi #(.ENABLE_OSERDES(0)) u_rgb2dvi 
	(
		//.TMDS_Clk_p		(hdmio_txc_p_o), 	//	w_hdmio_txc), 
		//.TMDS_Clk_n		(hdmio_txc_n_o), 
		//.TMDS_Data_p	(hdmio_txd_p_o), 	//	w_hdmio_txd), 
		//.TMDS_Data_n 	(hdmio_txd_n_o), 
		
		.oe_i 		(1), 			//	Always enable output
		.bitflip_i 		(4'b0000), 		//	Reverse clock & data lanes. 
		
		.aRst			(1'b0), 
		.aRst_n		(1'b1), 
		
		.PixelClk		(clk_pixel        ),//pixel clk = 74.25M
		.SerialClk		(     ),//pixel clk *5 = 371.25M
		
        /* V0.3 / 10：原连接如下，现将四个信号统一改为处理链输出：
           .vid_pVSync(lcd_vs), .vid_pHSync(lcd_hs), .vid_pVDE(lcd_de),
           .vid_pData(HDMI_TEST_PATTERN ? 24'hFF00FF : {lcd_red,lcd_green,lcd_blue})
           纯色测试保留最高优先级，使用与 processed_rgb 对齐的同步信号。 */
        .vid_pVSync(processed_vs),
        .vid_pHSync(processed_hs),
        .vid_pVDE(processed_de),
        .vid_pData(HDMI_TEST_PATTERN ? 24'hFF00FF : processed_rgb),
		
		.txc_o			(hdmi_txc_o), 
		.txd0_o			(hdmi_txd0_o), 
		.txd1_o			(hdmi_txd1_o), 
		.txd2_o			(hdmi_txd2_o)
	); 
		
	






	
	
endmodule


