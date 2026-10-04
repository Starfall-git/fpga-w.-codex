`timescale 1ns/1ps
module cnn_axi_adapter_tb;
localparam DATA_WIDTH=128,ADDR_WIDTH=32,ID_WIDTH=8;
reg  clk=0;
reg  rst=0;
wire  io_ddr_arw_valid;
reg  io_ddr_arw_ready=0;
wire [ADDR_WIDTH-1:0] io_ddr_arw_payload_addr;
wire [ID_WIDTH-1:0] io_ddr_arw_payload_id;
wire [7:0] io_ddr_arw_payload_len;
wire [2:0] io_ddr_arw_payload_size;
wire [1:0] io_ddr_arw_payload_burst;
wire [1:0] io_ddr_arw_payload_lock;
wire  io_ddr_arw_payload_write;
wire [ID_WIDTH-1:0] io_ddr_w_payload_id;
wire  io_ddr_w_valid;
reg  io_ddr_w_ready=0;
wire [DATA_WIDTH-1:0] io_ddr_w_payload_data;
wire [(DATA_WIDTH/8)-1:0] io_ddr_w_payload_strb;
wire  io_ddr_w_payload_last;
reg  io_ddr_b_valid=0;
wire  io_ddr_b_ready;
reg [ID_WIDTH-1:0] io_ddr_b_payload_id=0;
reg [1:0] io_ddr_b_payload_resp=0;
reg  io_ddr_r_valid=0;
wire  io_ddr_r_ready;
reg [DATA_WIDTH-1:0] io_ddr_r_payload_data=0;
reg [ID_WIDTH-1:0] io_ddr_r_payload_id=0;
reg [1:0] io_ddr_r_payload_resp=0;
reg  io_ddr_r_payload_last=0;
reg [ID_WIDTH-1:0] s_axi_awid=0;
reg [ADDR_WIDTH-1:0] s_axi_awaddr=0;
reg [7:0] s_axi_awlen=0;
reg [2:0] s_axi_awsize=0;
reg [1:0] s_axi_awburst=0;
reg  s_axi_awlock=0;
reg [3:0] s_axi_awcache=0;
reg [2:0] s_axi_awprot=0;
reg [3:0] s_axi_awqos=0;
reg [3:0] s_axi_awregion=0;
reg  s_axi_awvalid=0;
wire  s_axi_awready;
reg [DATA_WIDTH-1:0] s_axi_wdata=0;
reg [(DATA_WIDTH/8)-1:0] s_axi_wstrb=0;
reg  s_axi_wlast=0;
reg  s_axi_wvalid=0;
wire  s_axi_wready;
wire [ID_WIDTH-1:0] s_axi_bid;
wire [1:0] s_axi_bresp;
wire  s_axi_bvalid;
reg  s_axi_bready=0;
reg [ID_WIDTH-1:0] s_axi_arid=0;
reg [ADDR_WIDTH-1:0] s_axi_araddr=0;
reg [7:0] s_axi_arlen=0;
reg [2:0] s_axi_arsize=0;
reg [1:0] s_axi_arburst=0;
reg  s_axi_arlock=0;
reg [3:0] s_axi_arcache=0;
reg [2:0] s_axi_arprot=0;
reg [3:0] s_axi_arqos=0;
reg [3:0] s_axi_arregion=0;
reg  s_axi_arvalid=0;
wire  s_axi_arready;
wire [ID_WIDTH-1:0] s_axi_rid;
wire [DATA_WIDTH-1:0] s_axi_rdata;
wire [1:0] s_axi_rresp;
wire  s_axi_rlast;
wire  s_axi_rvalid;
reg  s_axi_rready=0;
always #5 clk=~clk;
cnn_axi_full_to_half_duplex #(.DATA_WIDTH(128)) dut(
.clk(clk),
.rst(rst),
.io_ddr_arw_valid(io_ddr_arw_valid),
.io_ddr_arw_ready(io_ddr_arw_ready),
.io_ddr_arw_payload_addr(io_ddr_arw_payload_addr),
.io_ddr_arw_payload_id(io_ddr_arw_payload_id),
.io_ddr_arw_payload_len(io_ddr_arw_payload_len),
.io_ddr_arw_payload_size(io_ddr_arw_payload_size),
.io_ddr_arw_payload_burst(io_ddr_arw_payload_burst),
.io_ddr_arw_payload_lock(io_ddr_arw_payload_lock),
.io_ddr_arw_payload_write(io_ddr_arw_payload_write),
.io_ddr_w_payload_id(io_ddr_w_payload_id),
.io_ddr_w_valid(io_ddr_w_valid),
.io_ddr_w_ready(io_ddr_w_ready),
.io_ddr_w_payload_data(io_ddr_w_payload_data),
.io_ddr_w_payload_strb(io_ddr_w_payload_strb),
.io_ddr_w_payload_last(io_ddr_w_payload_last),
.io_ddr_b_valid(io_ddr_b_valid),
.io_ddr_b_ready(io_ddr_b_ready),
.io_ddr_b_payload_id(io_ddr_b_payload_id),
.io_ddr_b_payload_resp(io_ddr_b_payload_resp),
.io_ddr_r_valid(io_ddr_r_valid),
.io_ddr_r_ready(io_ddr_r_ready),
.io_ddr_r_payload_data(io_ddr_r_payload_data),
.io_ddr_r_payload_id(io_ddr_r_payload_id),
.io_ddr_r_payload_resp(io_ddr_r_payload_resp),
.io_ddr_r_payload_last(io_ddr_r_payload_last),
.s_axi_awid(s_axi_awid),
.s_axi_awaddr(s_axi_awaddr),
.s_axi_awlen(s_axi_awlen),
.s_axi_awsize(s_axi_awsize),
.s_axi_awburst(s_axi_awburst),
.s_axi_awlock(s_axi_awlock),
.s_axi_awcache(s_axi_awcache),
.s_axi_awprot(s_axi_awprot),
.s_axi_awqos(s_axi_awqos),
.s_axi_awregion(s_axi_awregion),
.s_axi_awvalid(s_axi_awvalid),
.s_axi_awready(s_axi_awready),
.s_axi_wdata(s_axi_wdata),
.s_axi_wstrb(s_axi_wstrb),
.s_axi_wlast(s_axi_wlast),
.s_axi_wvalid(s_axi_wvalid),
.s_axi_wready(s_axi_wready),
.s_axi_bid(s_axi_bid),
.s_axi_bresp(s_axi_bresp),
.s_axi_bvalid(s_axi_bvalid),
.s_axi_bready(s_axi_bready),
.s_axi_arid(s_axi_arid),
.s_axi_araddr(s_axi_araddr),
.s_axi_arlen(s_axi_arlen),
.s_axi_arsize(s_axi_arsize),
.s_axi_arburst(s_axi_arburst),
.s_axi_arlock(s_axi_arlock),
.s_axi_arcache(s_axi_arcache),
.s_axi_arprot(s_axi_arprot),
.s_axi_arqos(s_axi_arqos),
.s_axi_arregion(s_axi_arregion),
.s_axi_arvalid(s_axi_arvalid),
.s_axi_arready(s_axi_arready),
.s_axi_rid(s_axi_rid),
.s_axi_rdata(s_axi_rdata),
.s_axi_rresp(s_axi_rresp),
.s_axi_rlast(s_axi_rlast),
.s_axi_rvalid(s_axi_rvalid),
.s_axi_rready(s_axi_rready)
);

integer resp,i;
initial begin #20000;$fatal(1,"adapter timeout");end
initial begin
 rst=1;repeat(3)@(negedge clk);rst=0;
 // Simultaneous independent requests: vendor FSM gives AW precedence.
 s_axi_awvalid=1;s_axi_arvalid=1;s_axi_awaddr=32'h1000;s_axi_araddr=32'h2000;
 s_axi_awid=8'hc1;s_axi_arid=8'hd2;s_axi_awsize=4;s_axi_arsize=4;
 s_axi_awburst=1;s_axi_arburst=1;s_axi_awlen=3;s_axi_arlen=7;
 wait(io_ddr_arw_valid);#1;
 repeat(4)begin
  @(negedge clk);
  if(!io_ddr_arw_valid||!io_ddr_arw_payload_write||io_ddr_arw_payload_addr!=32'h1000||io_ddr_arw_payload_id!=8'hc1||io_ddr_arw_payload_len!=3||s_axi_awready||s_axi_arready)$fatal(1,"stalled AW changed");
 end
 io_ddr_arw_ready=1;@(posedge clk);#1;@(negedge clk);s_axi_awvalid=0;io_ddr_arw_ready=0;
 wait(io_ddr_arw_valid);#1;
 if(io_ddr_arw_payload_write||io_ddr_arw_payload_addr!=32'h2000||io_ddr_arw_payload_id!=8'hd2||io_ddr_arw_payload_len!=7)$fatal(1,"AR lost");
 @(negedge clk);io_ddr_arw_ready=1;@(posedge clk);#1;@(negedge clk);s_axi_arvalid=0;io_ddr_arw_ready=0;
 // Every BRESP including DECERR must reach the accelerator, even under stall.
 for(resp=0;resp<4;resp=resp+1)begin
  io_ddr_b_valid=1;io_ddr_b_payload_resp=resp;io_ddr_b_payload_id=8'hc1;s_axi_bready=0;#1;
  if(!s_axi_bvalid||s_axi_bresp!=resp||s_axi_bid!=8'hc1||io_ddr_b_ready)$fatal(1,"B response swallowed");
  repeat(3)@(negedge clk);s_axi_bready=1;#1;if(!io_ddr_b_ready)$fatal(1,"B ready");
  @(negedge clk);io_ddr_b_valid=0;
 end
 s_axi_wdata=128'hfedcba9876543210;s_axi_wstrb=16'h4321;s_axi_wlast=1;s_axi_wvalid=1;io_ddr_w_ready=0;#1;
 if(!io_ddr_w_valid||io_ddr_w_payload_data!=s_axi_wdata||io_ddr_w_payload_strb!=16'h4321||!io_ddr_w_payload_last||s_axi_wready)$fatal(1,"W changed");
 io_ddr_w_ready=1;#1;if(!s_axi_wready)$fatal(1,"W ready");
 for(resp=0;resp<4;resp=resp+1)begin
  io_ddr_r_valid=1;io_ddr_r_payload_resp=resp;io_ddr_r_payload_data=128'h12345678;io_ddr_r_payload_id=8'hd2;io_ddr_r_payload_last=1;s_axi_rready=0;#1;
  if(!s_axi_rvalid||s_axi_rresp!=resp||s_axi_rid!=8'hd2||s_axi_rdata!=128'h12345678||!s_axi_rlast||io_ddr_r_ready)$fatal(1,"R changed");
  s_axi_rready=1;#1;if(!io_ddr_r_ready)$fatal(1,"R ready");@(negedge clk);
 end
 s_axi_arvalid=1;io_ddr_arw_ready=0;wait(io_ddr_arw_valid);@(negedge clk);rst=1;#1;
 if(io_ddr_arw_valid||s_axi_arready||s_axi_awready)$fatal(1,"reset address not cleared");
 $display("PASS CNN AXI adapter: official arbitration, stalled address, all B/R responses, IDs/data/strobes, reset");$finish;
end
endmodule
