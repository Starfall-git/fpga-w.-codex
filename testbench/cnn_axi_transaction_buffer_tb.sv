`timescale 1ns/1ps
module cnn_axi_transaction_buffer_tb;
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

 reg abort_i=0;
 wire quiescent_o;
 always #5 clk=~clk;
 cnn_axi_transaction_buffer dut(.*);
 integer addresses=0,writes=0;
 always @(posedge clk)begin
  if(m_avalid && m_aready)addresses=addresses+1;
  if(m_wvalid && m_wready)writes=writes+1;
 end
 task submit(input bit wr,input [7:0] n);
 begin
 @(negedge clk);s_addr=32'h12340;s_id=8'hc9;s_len=n;s_size=4;s_burst=1;s_lock=0;s_write=wr;s_avalid=1;
 while(!s_aready)@(negedge clk);
 @(negedge clk);s_avalid=0;
 end endtask
 task source_write(input integer n);
 integer j;
 begin
 for(j=0;j<n;j=j+1)begin
  repeat(j%3+1)@(negedge clk);
  if(m_avalid || m_wvalid)$fatal(1,"partial write reached memory");
  s_wdata=j;s_wstrb=16'ha55a^j;s_wlast=(j==n-1);s_wvalid=1;
  while(!s_wready)@(negedge clk);
  @(negedge clk);s_wvalid=0;
 end
 end endtask
 task accept_address;
 begin
 while(!m_avalid)@(negedge clk);
 if(m_addr!==32'h12340 || m_id!==8'hc9 || m_size!==4 || m_burst!==1)$fatal(1,"address snapshot");
 m_aready=1;@(negedge clk);m_aready=0;
 end endtask
 task drain_write(input integer n);
 integer j;
 reg [127:0] previous;
 begin
 for(j=0;j<n;j=j+1)begin
  while(!m_wvalid)@(negedge clk);
  if(m_wdata!==j || m_wstrb!==(16'ha55a^j[15:0]) || m_wlast!==(j==n-1))$fatal(1,"write contents %d",j);
  previous=m_wdata;
  repeat(j%4+1)begin @(negedge clk);if(!m_wvalid || m_wdata!==previous)$fatal(1,"write stall stability");end
  m_wready=1;@(negedge clk);m_wready=0;
 end
 m_bid=8'hc9;m_bresp=2;m_bvalid=1;
 while(!m_bready)@(negedge clk);
 @(negedge clk);m_bvalid=0;
 end endtask
 task fill_read(input integer n);
 integer j;
 begin
 for(j=0;j<n;j=j+1)begin
  m_rvalid=1;m_rid=8'hc9;m_rdata=j+1234;m_rresp=j%4;m_rlast=(j==n-1);
  #1;if(!m_rready)$fatal(1,"AI read backpressured DDR at %d",j);
  @(negedge clk);
 end
 m_rvalid=0;m_rlast=0;
 end endtask
 task consume_read(input integer n);
 integer j;
 begin
 for(j=0;j<n;j=j+1)begin
  while(!s_rvalid)@(negedge clk);
  if(s_rdata!==j+1234 || s_rresp!==(j%4) || s_rid!==8'hc9 || s_rlast!==(j==n-1))$fatal(1,"read snapshot %d",j);
  repeat(j%3+1)begin @(negedge clk);if(!s_rvalid || s_rdata!==j+1234)$fatal(1,"read stable");end
  s_rready=1;@(negedge clk);s_rready=0;
 end
 end endtask
 integer before_addr,before_w,k;
 initial begin
 #13;rst_n=1;
 // Maximal burst fills all RAM slots before a single DDR address is allowed.
 submit(1,255);source_write(256);
 s_addr=0;s_id=0;s_wdata='1;s_wstrb=0;
 repeat(5)@(negedge clk);accept_address();drain_write(256);
 if(!s_bvalid || s_bresp!==2 || s_bid!==8'hc9)$fatal(1,"buffered B");
 repeat(5)begin @(negedge clk);if(m_bready || !s_bvalid)$fatal(1,"B hold");end
 s_bready=1;@(negedge clk);s_bready=0;
 submit(0,255);accept_address();fill_read(256);
 repeat(5)@(negedge clk);consume_read(256);
 if(!quiescent_o)$fatal(1,"read completion");
 // Reset while collecting cancels locally, with no shared-memory activity.
 before_addr=addresses;submit(1,3);
 s_wvalid=1;s_wdata=0;s_wstrb='1;s_wlast=0;
 @(negedge clk);s_wvalid=0;abort_i=1;
 repeat(3)@(negedge clk);
 if(!quiescent_o || m_avalid || addresses!=before_addr)$fatal(1,"partial abort");
 abort_i=0;
 // Once VALID is asserted it must remain, even if AI resets before READY.
 submit(1,3);source_write(4);abort_i=1;
 repeat(4)begin @(negedge clk);if(!m_avalid)$fatal(1,"withdrawn VALID on abort");end
 before_w=writes;accept_address();drain_write(4);
 if(!quiescent_o || s_bvalid || writes-before_w!=4)$fatal(1,"issued write not drained");
 abort_i=0;
 // Issued read drains the whole burst with no upstream readiness and no reply after reset.
 submit(0,3);accept_address();abort_i=1;fill_read(4);
 repeat(3)@(negedge clk);
 if(!quiescent_o || s_rvalid)$fatal(1,"read abort did not drain");
 abort_i=0;
 // Bad WLAST is refused before consuming DDR, even though all data arrived.
 before_addr=addresses;submit(1,0);s_wvalid=1;s_wlast=0;
 @(negedge clk);s_wvalid=0;
 if(!s_bvalid || s_bresp!==2 || m_avalid || addresses!=before_addr)$fatal(1,"malformed write escaped");
 s_bready=1;@(negedge clk);s_bready=0;
 // Recovery after abort is real: a new transaction is returned correctly.
 submit(0,0);accept_address();fill_read(1);consume_read(1);
 $display("PASS CNN transaction buffer: 256-beat writes/reads, independent stalls, abort drain, malformed WLAST and recovery");
 $finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
