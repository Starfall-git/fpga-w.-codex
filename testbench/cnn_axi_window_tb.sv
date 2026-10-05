`timescale 1ns/1ps
module cnn_axi_window_tb;
reg  clk=0;
reg  rst_n=0;
reg  s_avalid=0;
wire  s_aready;
reg [31:0] s_addr=0;
reg [7:0] s_id=0;
reg [7:0] s_len=0;
reg [2:0] s_size=0;
reg [1:0] s_burst=0;
reg  s_write=0;
reg  s_lock=0;
reg  s_wvalid=0;
wire  s_wready;
reg [127:0] s_wdata=0;
reg [15:0] s_wstrb=0;
reg  s_wlast=0;
wire  s_bvalid;
reg  s_bready=0;
wire [7:0] s_bid;
wire [1:0] s_bresp;
wire  s_rvalid;
reg  s_rready=0;
wire [127:0] s_rdata;
wire [7:0] s_rid;
wire [1:0] s_rresp;
wire  s_rlast;
wire  m_avalid;
reg  m_aready=0;
wire [31:0] m_addr;
wire [7:0] m_id;
wire [7:0] m_len;
wire [2:0] m_size;
wire [1:0] m_burst;
wire  m_write;
wire  m_lock;
wire  m_wvalid;
reg  m_wready=0;
wire [127:0] m_wdata;
wire [15:0] m_wstrb;
wire  m_wlast;
reg  m_bvalid=0;
wire  m_bready;
reg [7:0] m_bid=0;
reg [1:0] m_bresp=0;
reg  m_rvalid=0;
wire  m_rready;
reg [127:0] m_rdata=0;
reg [7:0] m_rid=0;
reg [1:0] m_rresp=0;
reg  m_rlast=0;
 always #5 clk=~clk;
 cnn_axi_window dut(.*);
 integer forwards=0;
 always @(posedge clk)if(m_avalid && m_aready)forwards=forwards+1;
 task address(input [31:0] a,input [7:0] n,input bit write_op,input bit ok);
 begin
 @(negedge clk);s_addr=a;s_len=n;s_id=8'hb7;s_write=write_op;s_avalid=1;
 #1;if(m_avalid!==ok || !s_aready)$fatal(1,"address gate %h",a);
 if(ok && m_addr!=={a[31:4],4'b0}+32'h03fff000)$fatal(1,"translation %h",m_addr);
 @(negedge clk);s_avalid=0;
 end endtask
 task error_read(input [31:0] a,input [7:0] n);
 integer j,before_count;
 begin
 before_count=forwards;address(a,n,0,0);
 repeat(3)begin @(negedge clk);if(!s_rvalid || s_rid!==8'hb7 || s_rresp!==3 || s_rdata!==0)$fatal(1,"error read stall");end
 s_rready=1;
 for(j=0;j<=n;j=j+1) begin
 #1;if(!s_rvalid || s_rlast!==(j==n))$fatal(1,"error read length");
 @(negedge clk);
 end
 s_rready=0;
 if(forwards!=before_count || s_rvalid)$fatal(1,"error touched memory or extra beat");
 end endtask
 integer k,expected_forwards;
 initial begin
 #13;rst_n=1;s_size=4;s_burst=1;m_aready=1;
 address(32'h1000,1,1,1);
 // Real backpressure must preserve all data/byte enables.
 s_wvalid=1;s_wdata=128'h0123456789abcdef;s_wstrb=16'h35a7;
 #1;if(s_wready || !m_wvalid || m_wdata!==s_wdata || m_wstrb!==s_wstrb)$fatal(1,"write stall");
 repeat(2)@(negedge clk);m_wready=1;
 @(negedge clk);s_wlast=1;
 @(negedge clk);s_wvalid=0;s_wlast=0;m_bvalid=1;m_bid=8'hb7;m_bresp=2;
 #1;if(!s_bvalid || s_bresp!==2 || s_bid!==8'hb7 || m_bready)$fatal(1,"B response");
 @(negedge clk);s_bready=1;
 @(negedge clk);s_bready=0;m_bvalid=0;
 // Last legal 16-byte transaction at upper end of virtual window.
 address(32'h04000ff0,0,0,1);
 m_rvalid=1;m_rdata=128'hfedcba;m_rid=8'hb7;m_rresp=0;m_rlast=1;
 #1;if(!s_rvalid || s_rdata!==m_rdata || s_rid!==8'hb7 || m_rready)$fatal(1,"read stall");
 repeat(3)@(negedge clk);s_rready=1;
 @(negedge clk);s_rready=0;m_rvalid=0;m_rlast=0;
 error_read(32'h00000ff0,0); // below virtual region
 error_read(32'h04000ff0,1); // burst crosses end, even though start is legal
 error_read(32'hffffffff,255); // address overflow
 error_read(32'h00001ff0,1); // AXI 4KiB boundary
 // Official CPU store pattern: four 32-bit lanes in one 128-bit beat.
 for(k=0;k<4;k=k+1) begin
 address(32'h1000+k*4,0,1,1);
 s_wvalid=1;s_wlast=1;s_wdata=128'hddeeff0099aabbcc5566778811223344;
 s_wstrb=16'h000f << (k*4);m_wready=1;
 #1;if(!m_wvalid || m_wstrb!==s_wstrb || m_wdata!==s_wdata)$fatal(1,"CPU lane store");
 @(negedge clk);s_wvalid=0;s_wlast=0;m_bvalid=1;m_bresp=0;s_bready=1;
 @(negedge clk);m_bvalid=0;s_bready=0;
 end
 // The final byte of a page/window belongs to its last aligned beat.
 address(32'h04000fff,0,0,1);
 m_rvalid=1;m_rlast=1;s_rready=1;
 @(negedge clk);m_rvalid=0;m_rlast=0;s_rready=0;
 error_read(32'h00001ffc,1); // unaligned burst still crosses 4KiB
 error_read(32'h04000ffc,1); // unaligned burst still crosses window
 s_size=2;error_read(32'h1000,0);s_size=4;
 s_burst=0;error_read(32'h1000,0);s_burst=1;
 s_lock=1;error_read(32'h1000,0);s_lock=0;
 // Invalid writes drain exactly AWLEN+1 beats and emit one DECERR.
 expected_forwards=forwards;address(32'h04001000,2,1,0);
 s_wvalid=1;
 for(k=0;k<3;k=k+1) begin
 #1;if(!s_wready || m_wvalid || m_avalid)$fatal(1,"invalid write escaped");
 @(negedge clk);
 end
 s_wvalid=0;
 #1;if(!s_bvalid || s_bresp!==3 || s_bid!==8'hb7)$fatal(1,"invalid write reply");
 repeat(2)@(negedge clk);s_bready=1;
 @(negedge clk);s_bready=0;
 if(forwards!=expected_forwards)$fatal(1,"invalid write touched DDR");
 // Address valid remains stable while downstream refuses a legal command.
 m_aready=0;s_avalid=1;s_addr=32'h2000;s_len=0;
 repeat(3)begin @(negedge clk);if(s_aready || !m_avalid || m_addr!==32'h04001000)$fatal(1,"address stall");end
 s_avalid=0;rst_n=0;
 @(negedge clk);if(s_bvalid || s_rvalid || m_avalid || m_wvalid)$fatal(1,"reset outputs");
 $display("PASS CNN memory window: relocation, boundary/overflow rejection, burst drain, response ID and stalls");
 $finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
