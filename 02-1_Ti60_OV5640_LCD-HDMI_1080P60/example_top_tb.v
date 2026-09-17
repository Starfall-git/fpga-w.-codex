`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer:
//
// Create Date:   15:29:12 05/15/2023
// Design Name:   example_top
// Module Name:   D:/SVN_Path/DevKitProjects/Ti60/Dev/Ti60_SC130GS_DDR_DSI/example_top_tb.v
// Project Name:  Ti60_SC130GS_DDR_DSI
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

module example_top_tb;

	// Inputs
	reg nrst;
	reg clk_24m;
	reg pllin1;
	reg pll_dsi_lock;
	reg clk_48m_i;
	reg dsi_byteclk_i;
	reg dsi_serclk_i;
	reg dsi_txcclk_i;
	reg clk;
	reg clk_cmos;
	reg clk_pixel;
	reg clk_pixel_5x;
	reg core_clk;
	reg twd_clk;
	reg tdqss_clk;
	reg tac_clk;
	reg pll_lock;
	reg pll1_lock;
	reg cmos_sdat_IN;
	reg cmos_pclk;
	reg cmos_vsync;
	reg cmos_href;
	reg [7:0] cmos_data;
	reg cmos_ctl1;
	reg [1:0] i_dqs_hi;
	reg [1:0] i_dqs_lo;
	reg [1:0] i_dqs_n_hi;
	reg [1:0] i_dqs_n_lo;
	reg [15:0] i_dq_hi;
	reg [15:0] i_dq_lo;
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

	// Outputs
	wire pll_dsi_rstn_o;
	wire cmos_sclk;
	wire cmos_sdat_OUT;
	wire cmos_sdat_OE;
	wire cmos_ctl2;
	wire cmos_ctl3;
	wire hdmi_tx_clk_n_HI;
	wire hdmi_tx_clk_n_LO;
	wire hdmi_tx_clk_p_HI;
	wire hdmi_tx_clk_p_LO;
	wire [2:0] hdmi_tx_data_n_HI;
	wire [2:0] hdmi_tx_data_n_LO;
	wire [2:0] hdmi_tx_data_p_HI;
	wire [2:0] hdmi_tx_data_p_LO;
	wire lcd_pwm;
	wire reset;
	wire cs;
	wire ras;
	wire cas;
	wire we;
	wire cke;
	wire [15:0] addr;
	wire [2:0] ba;
	wire odt;
	wire [1:0] o_dm_hi;
	wire [1:0] o_dm_lo;
	wire [1:0] o_dqs_hi;
	wire [1:0] o_dqs_lo;
	wire [1:0] o_dqs_n_hi;
	wire [1:0] o_dqs_n_lo;
	wire [1:0] o_dqs_oe;
	wire [1:0] o_dqs_n_oe;
	wire [15:0] o_dq_hi;
	wire [15:0] o_dq_lo;
	wire [15:0] o_dq_oe;
	wire [2:0] shift;
	wire [4:0] shift_sel;
	wire shift_ena;
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
	wire dsi_reset_o;
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
	wire [1:0] led_o;

	// Instantiate the Unit Under Test (UUT)
	always #12 clk_pixel = ~clk_pixel; 
	
	reg 			r_dsi_serclk = 0; 
	always #2.976 r_dsi_serclk = ~r_dsi_serclk; 
	always @(r_dsi_serclk) #2.232 dsi_txcclk_i = r_dsi_serclk; 
	always @(r_dsi_serclk) #0.744 dsi_serclk_i = r_dsi_serclk; 
	reg 	[1:0] 	rc_dsi_clk = 0; 
	always @(posedge r_dsi_serclk)
		rc_dsi_clk <= rc_dsi_clk + 1; 
	
	always #10 clk = ~clk; 
	
	example_top #(.SIM_DATA(1)) uut (
		.nrst(nrst), 
		.clk_24m(clk_24m), 
		.pllin1(pllin1), 
		.pll_dsi_rstn_o(pll_dsi_rstn_o), 
		.pll_dsi_lock(pll_dsi_lock), 
		.clk_48m_i(clk_48m_i), 
		.dsi_byteclk_i(rc_dsi_clk[1]), 
		.dsi_serclk_i(dsi_serclk_i), 
		.dsi_txcclk_i(dsi_txcclk_i), 
		.clk(clk), 
		.clk_cmos(clk_cmos), 
		.clk_pixel(clk_pixel), 
		.clk_pixel_5x(clk_pixel_5x), 
		.core_clk(core_clk), 
		.twd_clk(twd_clk), 
		.tdqss_clk(tdqss_clk), 
		.tac_clk(tac_clk), 
		.pll_lock(pll_lock), 
		.pll1_lock(pll1_lock), 
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
		.hdmi_tx_clk_n_HI(hdmi_tx_clk_n_HI), 
		.hdmi_tx_clk_n_LO(hdmi_tx_clk_n_LO), 
		.hdmi_tx_clk_p_HI(hdmi_tx_clk_p_HI), 
		.hdmi_tx_clk_p_LO(hdmi_tx_clk_p_LO), 
		.hdmi_tx_data_n_HI(hdmi_tx_data_n_HI), 
		.hdmi_tx_data_n_LO(hdmi_tx_data_n_LO), 
		.hdmi_tx_data_p_HI(hdmi_tx_data_p_HI), 
		.hdmi_tx_data_p_LO(hdmi_tx_data_p_LO), 
		.lcd_pwm(lcd_pwm), 
		.reset(reset), 
		.cs(cs), 
		.ras(ras), 
		.cas(cas), 
		.we(we), 
		.cke(cke), 
		.addr(addr), 
		.ba(ba), 
		.odt(odt), 
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
		.i_dq_hi(i_dq_hi), 
		.i_dq_lo(i_dq_lo), 
		.o_dq_hi(o_dq_hi), 
		.o_dq_lo(o_dq_lo), 
		.o_dq_oe(o_dq_oe), 
		.shift(shift), 
		.shift_sel(shift_sel), 
		.shift_ena(shift_ena), 
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
		.dsi_reset_o(dsi_reset_o), 
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
		.led_o(led_o)
	);

	initial begin
		// Initialize Inputs
		nrst = 0;
		clk_24m = 0;
		pllin1 = 0;
		pll_dsi_lock = 0;
		clk_48m_i = 0;
		dsi_byteclk_i = 0;
		dsi_serclk_i = 0;
		dsi_txcclk_i = 0;
		clk = 0;
		clk_cmos = 0;
		clk_pixel = 0;
		clk_pixel_5x = 0;
		core_clk = 0;
		twd_clk = 0;
		tdqss_clk = 0;
		tac_clk = 0;
		pll_lock = 0;
		pll1_lock = 0;
		cmos_sdat_IN = 0;
		cmos_pclk = 0;
		cmos_vsync = 0;
		cmos_href = 0;
		cmos_data = 0;
		cmos_ctl1 = 0;
		i_dqs_hi = 0;
		i_dqs_lo = 0;
		i_dqs_n_hi = 0;
		i_dqs_n_lo = 0;
		i_dq_hi = 0;
		i_dq_lo = 0;
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

		// Wait 100 ns for global reset to finish
		#100; nrst = 1; pll_lock = 1; pll1_lock = 1; pll_dsi_lock = 1; #96; 
        
		// Add stimulus here

	end
      
endmodule

