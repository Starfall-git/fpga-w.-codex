`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer:
//
// Create Date:   01:14:23 06/21/2023
// Design Name:   example_top
// Module Name:   D:/SVN_Path/DevKitProjects/Ti60/Dev/01_Ti60_AR0135_LCD/example_top_tb2.v
// Project Name:  Ti60_AR0135_LCD
// Target Device:  
// Tool versions:  
// Description: 
//
// Verilog Test Fixture created by ISE for module: example_top
//
// Dependencies:
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
////////////////////////////////////////////////////////////////////////////////

module example_top_tb2;

	// Inputs
	reg clk_24m;
	reg clk_25m;
	reg clk_sys;
	reg clk_pixel;
	reg clk_pixel_2x;
	reg clk_pixel_10x;
	reg sys_pll_lock;
	reg dsi_refclk_i;
	reg dsi_byteclk_i;
	reg dsi_serclk_i;
	reg dsi_txcclk_i;
	reg dsi_pll_lock;
	reg tdqss_clk;
	reg core_clk;
	reg tac_clk;
	reg twd_clk;
	reg ddr_pll_lock;
	reg clk_lvds_1x;
	reg clk_lvds_7x;
	reg clk_27m;
	reg clk_54m;
	reg lvds_pll_lock;
	reg [15:0] i_dq_hi;
	reg [15:0] i_dq_lo;
	reg [1:0] i_dqs_hi;
	reg [1:0] i_dqs_lo;
	reg [1:0] i_dqs_n_hi;
	reg [1:0] i_dqs_n_lo;
	reg csi_ctl0_i;
	reg csi_ctl1_i;
	reg csi_scl_i;
	reg csi_sda_i;
	reg csi_rxc_lp_p_i;
	reg csi_rxc_lp_n_i;
	reg csi_rxc_i;
	reg csi_rxd0_lp_p_i;
	reg csi_rxd0_lp_n_i;
	reg [7:0] csi_rxd0_hs_i;
	reg csi_rxd0_fifo_empty_i;
	reg csi_rxd1_lp_n_i;
	reg csi_rxd1_lp_p_i;
	reg [7:0] csi_rxd1_hs_i;
	reg csi_rxd1_fifo_empty_i;
	reg csi_rxd2_lp_p_i;
	reg csi_rxd2_lp_n_i;
	reg [7:0] csi_rxd2_hs_i;
	reg csi_rxd2_fifo_empty_i;
	reg csi_rxd3_lp_p_i;
	reg csi_rxd3_lp_n_i;
	reg [7:0] csi_rxd3_hs_i;
	reg csi_rxd3_fifo_empty_i;
	reg dsi_txd0_lp_p_i;
	reg dsi_txd0_lp_n_i;
	reg dsi_txd1_lp_p_i;
	reg dsi_txd1_lp_n_i;
	reg dsi_txd2_lp_p_i;
	reg dsi_txd2_lp_n_i;
	reg dsi_txd3_lp_p_i;
	reg dsi_txd3_lp_n_i;
	reg uart_rx_i;
	reg cmos_sdat_IN;
	reg cmos_pclk;
	reg cmos_vsync;
	reg cmos_href;
	reg [7:0] cmos_data;
	reg cmos_ctl1;
	reg lcd_tp_sda_i;
	reg lcd_tp_scl_i;
	reg lcd_tp_int_i;

	// Outputs
	wire sys_pll_rstn_o;
	wire dsi_pll_rstn_o;
	wire ddr_pll_rstn_o;
	wire [2:0] shift;
	wire [4:0] shift_sel;
	wire shift_ena;
	wire lvds_pll_rstn_o;
	wire [15:0] addr;
	wire [2:0] ba;
	wire we;
	wire reset;
	wire ras;
	wire cas;
	wire odt;
	wire cke;
	wire cs;
	wire [15:0] o_dq_hi;
	wire [15:0] o_dq_lo;
	wire [15:0] o_dq_oe;
	wire [1:0] o_dm_hi;
	wire [1:0] o_dm_lo;
	wire [1:0] o_dqs_hi;
	wire [1:0] o_dqs_lo;
	wire [1:0] o_dqs_n_hi;
	wire [1:0] o_dqs_n_lo;
	wire [1:0] o_dqs_oe;
	wire [1:0] o_dqs_n_oe;
	wire clk_p_hi;
	wire clk_p_lo;
	wire clk_n_hi;
	wire clk_n_lo;
	wire csi_ctl0_o;
	wire csi_ctl0_oe;
	wire csi_ctl1_o;
	wire csi_ctl1_oe;
	wire csi_scl_o;
	wire csi_scl_oe;
	wire csi_sda_o;
	wire csi_sda_oe;
	wire csi_rxc_hs_en_o;
	wire csi_rxc_hs_term_en_o;
	wire csi_rxd0_rst_o;
	wire csi_rxd0_hs_en_o;
	wire csi_rxd0_hs_term_en_o;
	wire csi_rxd0_fifo_rd_o;
	wire csi_rxd1_rst_o;
	wire csi_rxd1_hs_en_o;
	wire csi_rxd1_hs_term_en_o;
	wire csi_rxd1_fifo_rd_o;
	wire csi_rxd2_rst_o;
	wire csi_rxd2_hs_en_o;
	wire csi_rxd2_hs_term_en_o;
	wire csi_rxd2_fifo_rd_o;
	wire csi_rxd3_rst_o;
	wire csi_rxd3_hs_en_o;
	wire csi_rxd3_hs_term_en_o;
	wire csi_rxd3_fifo_rd_o;
	wire dsi_pwm_o;
	wire dsi_resetn_o;
	wire dsi_txc_rst_o;
	wire dsi_txc_lp_p_oe;
	wire dsi_txc_lp_p_o;
	wire dsi_txc_lp_n_oe;
	wire dsi_txc_lp_n_o;
	wire dsi_txc_hs_oe;
	wire [7:0] dsi_txc_hs_o;
	wire dsi_txd0_rst_o;
	wire dsi_txd0_hs_oe;
	wire [7:0] dsi_txd0_hs_o;
	wire dsi_txd0_lp_p_oe;
	wire dsi_txd0_lp_p_o;
	wire dsi_txd0_lp_n_oe;
	wire dsi_txd0_lp_n_o;
	wire dsi_txd1_rst_o;
	wire dsi_txd1_lp_p_oe;
	wire dsi_txd1_lp_p_o;
	wire dsi_txd1_lp_n_oe;
	wire dsi_txd1_lp_n_o;
	wire dsi_txd1_hs_oe;
	wire [7:0] dsi_txd1_hs_o;
	wire dsi_txd2_rst_o;
	wire dsi_txd2_lp_p_oe;
	wire dsi_txd2_lp_p_o;
	wire dsi_txd2_lp_n_oe;
	wire dsi_txd2_lp_n_o;
	wire dsi_txd2_hs_oe;
	wire [7:0] dsi_txd2_hs_o;
	wire dsi_txd3_rst_o;
	wire dsi_txd3_lp_p_oe;
	wire dsi_txd3_lp_p_o;
	wire dsi_txd3_lp_n_oe;
	wire dsi_txd3_lp_n_o;
	wire dsi_txd3_hs_oe;
	wire [7:0] dsi_txd3_hs_o;
	wire uart_tx_o;
	wire [5:0] led_o;
	wire cmos_sclk;
	wire cmos_sdat_OUT;
	wire cmos_sdat_OE;
	wire cmos_ctl2;
	wire cmos_ctl3;
	wire hdmi_txc_oe;
	wire hdmi_txd0_oe;
	wire hdmi_txd1_oe;
	wire hdmi_txd2_oe;
	wire hdmi_txc_rst_o;
	wire hdmi_txd0_rst_o;
	wire hdmi_txd1_rst_o;
	wire hdmi_txd2_rst_o;
	wire [9:0] hdmi_txc_o;
	wire [9:0] hdmi_txd0_o;
	wire [9:0] hdmi_txd1_o;
	wire [9:0] hdmi_txd2_o;
	wire lvds_txc_oe;
	wire [6:0] lvds_txc_o;
	wire lvds_txc_rst_o;
	wire lvds_txd0_oe;
	wire [6:0] lvds_txd0_o;
	wire lvds_txd0_rst_o;
	wire lvds_txd1_oe;
	wire [6:0] lvds_txd1_o;
	wire lvds_txd1_rst_o;
	wire lvds_txd2_oe;
	wire [6:0] lvds_txd2_o;
	wire lvds_txd2_rst_o;
	wire lvds_txd3_oe;
	wire [6:0] lvds_txd3_o;
	wire lvds_txd3_rst_o;
	wire lcd_tp_sda_o;
	wire lcd_tp_sda_oe;
	wire lcd_tp_scl_o;
	wire lcd_tp_scl_oe;
	wire lcd_tp_int_o;
	wire lcd_tp_int_oe;
	wire lcd_tp_rst_o;
	wire lcd_pwm_o;
	wire lcd_blen_o;
	wire lcd_pclk_o;
	wire lcd_vs_o;
	wire lcd_hs_o;
	wire lcd_de_o;
	wire [7:0] lcd_b7_0_o;
	wire [7:0] lcd_g7_0_o;
	wire [7:0] lcd_r7_0_o;
	
	always #20.833 clk_24m = ~clk_24m; 
	always #20 clk_25m = ~clk_25m; 
	always #5 clk_sys = ~clk_sys; 
	always #2.5 core_clk = ~core_clk; 
	always #8 clk_lvds_1x = ~clk_lvds_1x; 

	// Instantiate the Unit Under Test (UUT)
	example_top uut (
		.clk_24m(clk_24m), 
		.clk_25m(clk_25m), 
		.sys_pll_rstn_o(sys_pll_rstn_o), 
		.clk_sys(clk_sys), 
		.clk_pixel(clk_pixel), 
		.clk_pixel_2x(clk_pixel_2x), 
		.clk_pixel_10x(clk_pixel_10x), 
		.sys_pll_lock(sys_pll_lock), 
		.dsi_pll_rstn_o(dsi_pll_rstn_o), 
		.dsi_refclk_i(dsi_refclk_i), 
		.dsi_byteclk_i(dsi_byteclk_i), 
		.dsi_serclk_i(dsi_serclk_i), 
		.dsi_txcclk_i(dsi_txcclk_i), 
		.dsi_pll_lock(dsi_pll_lock), 
		.ddr_pll_rstn_o(ddr_pll_rstn_o), 
		.tdqss_clk(tdqss_clk), 
		.core_clk(core_clk), 
		.tac_clk(tac_clk), 
		.twd_clk(twd_clk), 
		.ddr_pll_lock(ddr_pll_lock), 
		.shift(shift), 
		.shift_sel(shift_sel), 
		.shift_ena(shift_ena), 
		.lvds_pll_rstn_o(lvds_pll_rstn_o), 
		.clk_lvds_1x(clk_lvds_1x), 
		.clk_lvds_7x(clk_lvds_7x), 
		.clk_27m(clk_27m), 
		.clk_54m(clk_54m), 
		.lvds_pll_lock(lvds_pll_lock), 
		.addr(addr), 
		.ba(ba), 
		.we(we), 
		.reset(reset), 
		.ras(ras), 
		.cas(cas), 
		.odt(odt), 
		.cke(cke), 
		.cs(cs), 
		.i_dq_hi(i_dq_hi), 
		.i_dq_lo(i_dq_lo), 
		.o_dq_hi(o_dq_hi), 
		.o_dq_lo(o_dq_lo), 
		.o_dq_oe(o_dq_oe), 
		.o_dm_hi(o_dm_hi), 
		.o_dm_lo(o_dm_lo), 
		.i_dqs_hi(i_dqs_hi), 
		.i_dqs_lo(i_dqs_lo), 
		.i_dqs_n_hi(i_dqs_n_hi), 
		.i_dqs_n_lo(i_dqs_n_lo), 
		.o_dqs_hi(o_dqs_hi), 
		.o_dqs_lo(o_dqs_lo), 
		.o_dqs_n_hi(o_dqs_n_hi), 
		.o_dqs_n_lo(o_dqs_n_lo), 
		.o_dqs_oe(o_dqs_oe), 
		.o_dqs_n_oe(o_dqs_n_oe), 
		.clk_p_hi(clk_p_hi), 
		.clk_p_lo(clk_p_lo), 
		.clk_n_hi(clk_n_hi), 
		.clk_n_lo(clk_n_lo), 
		.csi_ctl0_o(csi_ctl0_o), 
		.csi_ctl0_oe(csi_ctl0_oe), 
		.csi_ctl0_i(csi_ctl0_i), 
		.csi_ctl1_o(csi_ctl1_o), 
		.csi_ctl1_oe(csi_ctl1_oe), 
		.csi_ctl1_i(csi_ctl1_i), 
		.csi_scl_o(csi_scl_o), 
		.csi_scl_oe(csi_scl_oe), 
		.csi_scl_i(csi_scl_i), 
		.csi_sda_o(csi_sda_o), 
		.csi_sda_oe(csi_sda_oe), 
		.csi_sda_i(csi_sda_i), 
		.csi_rxc_lp_p_i(csi_rxc_lp_p_i), 
		.csi_rxc_lp_n_i(csi_rxc_lp_n_i), 
		.csi_rxc_hs_en_o(csi_rxc_hs_en_o), 
		.csi_rxc_hs_term_en_o(csi_rxc_hs_term_en_o), 
		.csi_rxc_i(csi_rxc_i), 
		.csi_rxd0_rst_o(csi_rxd0_rst_o), 
		.csi_rxd0_hs_en_o(csi_rxd0_hs_en_o), 
		.csi_rxd0_hs_term_en_o(csi_rxd0_hs_term_en_o), 
		.csi_rxd0_lp_p_i(csi_rxd0_lp_p_i), 
		.csi_rxd0_lp_n_i(csi_rxd0_lp_n_i), 
		.csi_rxd0_hs_i(csi_rxd0_hs_i), 
		.csi_rxd0_fifo_rd_o(csi_rxd0_fifo_rd_o), 
		.csi_rxd0_fifo_empty_i(csi_rxd0_fifo_empty_i), 
		.csi_rxd1_rst_o(csi_rxd1_rst_o), 
		.csi_rxd1_hs_en_o(csi_rxd1_hs_en_o), 
		.csi_rxd1_hs_term_en_o(csi_rxd1_hs_term_en_o), 
		.csi_rxd1_lp_n_i(csi_rxd1_lp_n_i), 
		.csi_rxd1_lp_p_i(csi_rxd1_lp_p_i), 
		.csi_rxd1_hs_i(csi_rxd1_hs_i), 
		.csi_rxd1_fifo_rd_o(csi_rxd1_fifo_rd_o), 
		.csi_rxd1_fifo_empty_i(csi_rxd1_fifo_empty_i), 
		.csi_rxd2_rst_o(csi_rxd2_rst_o), 
		.csi_rxd2_hs_en_o(csi_rxd2_hs_en_o), 
		.csi_rxd2_hs_term_en_o(csi_rxd2_hs_term_en_o), 
		.csi_rxd2_lp_p_i(csi_rxd2_lp_p_i), 
		.csi_rxd2_lp_n_i(csi_rxd2_lp_n_i), 
		.csi_rxd2_hs_i(csi_rxd2_hs_i), 
		.csi_rxd2_fifo_rd_o(csi_rxd2_fifo_rd_o), 
		.csi_rxd2_fifo_empty_i(csi_rxd2_fifo_empty_i), 
		.csi_rxd3_rst_o(csi_rxd3_rst_o), 
		.csi_rxd3_hs_en_o(csi_rxd3_hs_en_o), 
		.csi_rxd3_hs_term_en_o(csi_rxd3_hs_term_en_o), 
		.csi_rxd3_lp_p_i(csi_rxd3_lp_p_i), 
		.csi_rxd3_lp_n_i(csi_rxd3_lp_n_i), 
		.csi_rxd3_hs_i(csi_rxd3_hs_i), 
		.csi_rxd3_fifo_rd_o(csi_rxd3_fifo_rd_o), 
		.csi_rxd3_fifo_empty_i(csi_rxd3_fifo_empty_i), 
		.dsi_pwm_o(dsi_pwm_o), 
		.dsi_resetn_o(dsi_resetn_o), 
		.dsi_txc_rst_o(dsi_txc_rst_o), 
		.dsi_txc_lp_p_oe(dsi_txc_lp_p_oe), 
		.dsi_txc_lp_p_o(dsi_txc_lp_p_o), 
		.dsi_txc_lp_n_oe(dsi_txc_lp_n_oe), 
		.dsi_txc_lp_n_o(dsi_txc_lp_n_o), 
		.dsi_txc_hs_oe(dsi_txc_hs_oe), 
		.dsi_txc_hs_o(dsi_txc_hs_o), 
		.dsi_txd0_rst_o(dsi_txd0_rst_o), 
		.dsi_txd0_hs_oe(dsi_txd0_hs_oe), 
		.dsi_txd0_hs_o(dsi_txd0_hs_o), 
		.dsi_txd0_lp_p_oe(dsi_txd0_lp_p_oe), 
		.dsi_txd0_lp_p_o(dsi_txd0_lp_p_o), 
		.dsi_txd0_lp_n_oe(dsi_txd0_lp_n_oe), 
		.dsi_txd0_lp_n_o(dsi_txd0_lp_n_o), 
		.dsi_txd1_rst_o(dsi_txd1_rst_o), 
		.dsi_txd1_lp_p_oe(dsi_txd1_lp_p_oe), 
		.dsi_txd1_lp_p_o(dsi_txd1_lp_p_o), 
		.dsi_txd1_lp_n_oe(dsi_txd1_lp_n_oe), 
		.dsi_txd1_lp_n_o(dsi_txd1_lp_n_o), 
		.dsi_txd1_hs_oe(dsi_txd1_hs_oe), 
		.dsi_txd1_hs_o(dsi_txd1_hs_o), 
		.dsi_txd2_rst_o(dsi_txd2_rst_o), 
		.dsi_txd2_lp_p_oe(dsi_txd2_lp_p_oe), 
		.dsi_txd2_lp_p_o(dsi_txd2_lp_p_o), 
		.dsi_txd2_lp_n_oe(dsi_txd2_lp_n_oe), 
		.dsi_txd2_lp_n_o(dsi_txd2_lp_n_o), 
		.dsi_txd2_hs_oe(dsi_txd2_hs_oe), 
		.dsi_txd2_hs_o(dsi_txd2_hs_o), 
		.dsi_txd3_rst_o(dsi_txd3_rst_o), 
		.dsi_txd3_lp_p_oe(dsi_txd3_lp_p_oe), 
		.dsi_txd3_lp_p_o(dsi_txd3_lp_p_o), 
		.dsi_txd3_lp_n_oe(dsi_txd3_lp_n_oe), 
		.dsi_txd3_lp_n_o(dsi_txd3_lp_n_o), 
		.dsi_txd3_hs_oe(dsi_txd3_hs_oe), 
		.dsi_txd3_hs_o(dsi_txd3_hs_o), 
		.dsi_txd0_lp_p_i(dsi_txd0_lp_p_i), 
		.dsi_txd0_lp_n_i(dsi_txd0_lp_n_i), 
		.dsi_txd1_lp_p_i(dsi_txd1_lp_p_i), 
		.dsi_txd1_lp_n_i(dsi_txd1_lp_n_i), 
		.dsi_txd2_lp_p_i(dsi_txd2_lp_p_i), 
		.dsi_txd2_lp_n_i(dsi_txd2_lp_n_i), 
		.dsi_txd3_lp_p_i(dsi_txd3_lp_p_i), 
		.dsi_txd3_lp_n_i(dsi_txd3_lp_n_i), 
		.uart_rx_i(uart_rx_i), 
		.uart_tx_o(uart_tx_o), 
		.led_o(led_o), 
		.cmos_sclk(cmos_sclk), 
		.cmos_sdat_IN(cmos_sdat_IN), 
		.cmos_sdat_OUT(cmos_sdat_OUT), 
		.cmos_sdat_OE(cmos_sdat_OE), 
		.cmos_pclk(cmos_pclk), 
		.cmos_vsync(cmos_vsync), 
		.cmos_href(cmos_href), 
		.cmos_data(cmos_data), 
		.cmos_ctl1(cmos_ctl1), 
		.cmos_ctl2(cmos_ctl2), 
		.cmos_ctl3(cmos_ctl3), 
		.hdmi_txc_oe(hdmi_txc_oe), 
		.hdmi_txd0_oe(hdmi_txd0_oe), 
		.hdmi_txd1_oe(hdmi_txd1_oe), 
		.hdmi_txd2_oe(hdmi_txd2_oe), 
		.hdmi_txc_rst_o(hdmi_txc_rst_o), 
		.hdmi_txd0_rst_o(hdmi_txd0_rst_o), 
		.hdmi_txd1_rst_o(hdmi_txd1_rst_o), 
		.hdmi_txd2_rst_o(hdmi_txd2_rst_o), 
		.hdmi_txc_o(hdmi_txc_o), 
		.hdmi_txd0_o(hdmi_txd0_o), 
		.hdmi_txd1_o(hdmi_txd1_o), 
		.hdmi_txd2_o(hdmi_txd2_o), 
		.lvds_txc_oe(lvds_txc_oe), 
		.lvds_txc_o(lvds_txc_o), 
		.lvds_txc_rst_o(lvds_txc_rst_o), 
		.lvds_txd0_oe(lvds_txd0_oe), 
		.lvds_txd0_o(lvds_txd0_o), 
		.lvds_txd0_rst_o(lvds_txd0_rst_o), 
		.lvds_txd1_oe(lvds_txd1_oe), 
		.lvds_txd1_o(lvds_txd1_o), 
		.lvds_txd1_rst_o(lvds_txd1_rst_o), 
		.lvds_txd2_oe(lvds_txd2_oe), 
		.lvds_txd2_o(lvds_txd2_o), 
		.lvds_txd2_rst_o(lvds_txd2_rst_o), 
		.lvds_txd3_oe(lvds_txd3_oe), 
		.lvds_txd3_o(lvds_txd3_o), 
		.lvds_txd3_rst_o(lvds_txd3_rst_o), 
		.lcd_tp_sda_o(lcd_tp_sda_o), 
		.lcd_tp_sda_oe(lcd_tp_sda_oe), 
		.lcd_tp_sda_i(lcd_tp_sda_i), 
		.lcd_tp_scl_o(lcd_tp_scl_o), 
		.lcd_tp_scl_oe(lcd_tp_scl_oe), 
		.lcd_tp_scl_i(lcd_tp_scl_i), 
		.lcd_tp_int_o(lcd_tp_int_o), 
		.lcd_tp_int_oe(lcd_tp_int_oe), 
		.lcd_tp_int_i(lcd_tp_int_i), 
		.lcd_tp_rst_o(lcd_tp_rst_o), 
		.lcd_pwm_o(lcd_pwm_o), 
		.lcd_blen_o(lcd_blen_o), 
		//.lcd_pclk_o(lcd_pclk_o), 
		.lcd_vs_o(lcd_vs_o), 
		.lcd_hs_o(lcd_hs_o), 
		.lcd_de_o(lcd_de_o), 
		.lcd_b7_0_o(lcd_b7_0_o), 
		.lcd_g7_0_o(lcd_g7_0_o), 
		.lcd_r7_0_o(lcd_r7_0_o)
	);
	
	always #18.518 clk_27m = ~clk_27m; 
	always #9.259 clk_54m = ~clk_54m; 
	
	always #10.833 dsi_refclk_i = ~dsi_refclk_i; 
	always #11.904 dsi_byteclk_i = ~dsi_byteclk_i; 
	always #2.976 dsi_serclk_i = ~dsi_serclk_i; 
	always #2.976 dsi_txcclk_i = ~dsi_serclk_i; 
	
	always #5 clk_pixel = ~clk_pixel; 
	always #2.5 clk_pixel_2x = ~clk_pixel_2x; 
	always #0.5 clk_pixel_10x = ~clk_pixel_10x; 
	

	initial begin
		// Initialize Inputs
		clk_24m = 0;
		clk_25m = 0;
		clk_sys = 0;
		clk_pixel = 0;
		clk_pixel_2x = 1;
		clk_pixel_10x = 1;
		sys_pll_lock = 0;
		dsi_refclk_i = 0;
		dsi_byteclk_i = 0;
		dsi_serclk_i = 0;
		dsi_txcclk_i = 0;
		dsi_pll_lock = 0;
		tdqss_clk = 0;
		core_clk = 1;
		tac_clk = 0;
		twd_clk = 0;
		ddr_pll_lock = 0;
		clk_lvds_1x = 0;
		clk_lvds_7x = 0;
		clk_27m = 0;
		clk_54m = 1;
		lvds_pll_lock = 0;
		i_dq_hi = 0;
		i_dq_lo = 0;
		i_dqs_hi = 0;
		i_dqs_lo = 0;
		i_dqs_n_hi = 0;
		i_dqs_n_lo = 0;
		csi_ctl0_i = 0;
		csi_ctl1_i = 0;
		csi_scl_i = 0;
		csi_sda_i = 0;
		csi_rxc_lp_p_i = 0;
		csi_rxc_lp_n_i = 0;
		csi_rxc_i = 0;
		csi_rxd0_lp_p_i = 0;
		csi_rxd0_lp_n_i = 0;
		csi_rxd0_hs_i = 0;
		csi_rxd0_fifo_empty_i = 0;
		csi_rxd1_lp_n_i = 0;
		csi_rxd1_lp_p_i = 0;
		csi_rxd1_hs_i = 0;
		csi_rxd1_fifo_empty_i = 0;
		csi_rxd2_lp_p_i = 0;
		csi_rxd2_lp_n_i = 0;
		csi_rxd2_hs_i = 0;
		csi_rxd2_fifo_empty_i = 0;
		csi_rxd3_lp_p_i = 0;
		csi_rxd3_lp_n_i = 0;
		csi_rxd3_hs_i = 0;
		csi_rxd3_fifo_empty_i = 0;
		dsi_txd0_lp_p_i = 0;
		dsi_txd0_lp_n_i = 0;
		dsi_txd1_lp_p_i = 0;
		dsi_txd1_lp_n_i = 0;
		dsi_txd2_lp_p_i = 0;
		dsi_txd2_lp_n_i = 0;
		dsi_txd3_lp_p_i = 0;
		dsi_txd3_lp_n_i = 0;
		uart_rx_i = 0;
		cmos_sdat_IN = 0;
		cmos_pclk = 0;
		cmos_vsync = 0;
		cmos_href = 0;
		cmos_data = 0;
		cmos_ctl1 = 0;
		lcd_tp_sda_i = 0;
		lcd_tp_scl_i = 0;
		lcd_tp_int_i = 0;

		// Wait 100 ns for global reset to finish
		#100; sys_pll_lock = 1; #200; ddr_pll_lock = 1; lvds_pll_lock = 1; dsi_pll_lock = 1; #96; 
        
		// Add stimulus here

	end
      
endmodule

