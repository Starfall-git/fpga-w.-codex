`timescale 1ns/1ps
module cnn_shared_ddr_tb;
reg  clk=0;
reg  rst_n=0;
reg [2:0] s_avalid=0;
wire [2:0] s_aready;
reg [95:0] s_addr=0;
reg [23:0] s_id=0;
reg [23:0] s_len=0;
reg [8:0] s_size=0;
reg [5:0] s_burst=0;
reg [2:0] s_write=0;
reg [2:0] s_lock=0;
reg [2:0] s_wvalid=0;
wire [2:0] s_wready;
reg [383:0] s_wdata=0;
reg [47:0] s_wstrb=0;
reg [2:0] s_wlast=0;
wire [2:0] s_bvalid;
reg [2:0] s_bready=0;
wire [23:0] s_bid;
wire [5:0] s_bresp;
wire [2:0] s_rvalid;
reg [2:0] s_rready=0;
wire [383:0] s_rdata;
wire [23:0] s_rid;
wire [5:0] s_rresp;
wire [2:0] s_rlast;
wire  m_avalid;
reg  m_aready=0;
wire [31:0] m_addr;
wire [3:0] m_id;
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
wire [3:0] m_wid;
reg  m_bvalid=0;
wire  m_bready;
reg [1:0] m_bresp=0;
reg  m_rvalid=0;
wire  m_rready;
reg [127:0] m_rdata=0;
reg [1:0] m_rresp=0;
reg  m_rlast=0;
wire  idle_o;

 reg [1:0] ai_abort=0;
 wire [1:0] ai_quiescent;
 always #5 clk=~clk;
 cnn_shared_ddr dut(.*);
 integer video_reads=0,cpu_beats_sent=0,ddr_writes=0,ai_reads=0,grants=0;
 reg cpu_done=0,ai_read_done=0;
 reg [3:0] owner;
 integer length,i,j,snapshot;
 initial begin
 #13;rst_n=1;
 s_addr={32'h2000,32'h1000,32'h100000};s_id={8'hd2,8'hc1,8'h80};
 s_len={8'd7,8'd255,8'd0};s_size={3'd4,3'd4,3'd4};s_burst={2'd1,2'd1,2'd1};
 s_write=3'b010;s_rready=3'b001;s_bready=0;
 end
 // Existing video continually requests frames/blocks and accepts responses.
 initial begin
 wait(rst_n);@(negedge clk);
 forever begin
  s_avalid[0]=1;do @(posedge clk);while(!s_aready[0]);
  @(negedge clk);s_avalid[0]=0;
  do @(posedge clk);while(!s_rvalid[0]);
  if(s_rid[7:0]!==8'h80 || !s_rlast[0] || s_rdata[127:0]!==128'hfeed)$fatal(1,"video response corruption");
  video_reads=video_reads+1;
  @(negedge clk);
 end
 end
 // CPU deliberately provides a slow 256-beat write, then remains reset.
 initial begin
 wait(rst_n);@(negedge clk);s_avalid[1]=1;
 while(!s_aready[1])@(negedge clk);
 @(negedge clk);s_avalid[1]=0;
 for(j=0;j<256;j=j+1)begin
  repeat(3)@(negedge clk);
  s_wvalid[1]=1;s_wdata[255:128]=j+4096;s_wstrb[31:16]=16'h1234;s_wlast[1]=(j==255);
  while(!s_wready[1])@(negedge clk);
  @(negedge clk);s_wvalid[1]=0;cpu_beats_sent=cpu_beats_sent+1;
 end
 end
 // TinyML requests a read but does not consume a single response until later.
 initial begin
 wait(rst_n);@(negedge clk);s_avalid[2]=1;
 while(!s_aready[2])@(negedge clk);
 @(negedge clk);s_avalid[2]=0;
 end
 // Independent behavioral DDR responds to only the currently accepted command.
 initial begin
 wait(rst_n);
 forever begin
  @(negedge clk);while(!m_avalid)@(negedge clk);
  owner=m_id;length=m_len+1;grants=grants+1;
  if(owner==0 && m_addr!==32'h100000)$fatal(1,"video address relocated");
  if(owner==1 && (m_addr!==32'h4000000 || cpu_beats_sent!=256))$fatal(1,"partial CPU burst admitted");
  if(owner==2 && m_addr!==32'h4001000)$fatal(1,"AI address not relocated");
  m_aready=1;@(negedge clk);m_aready=0;
  if(owner==1)begin
   for(i=0;i<length;i=i+1)begin
    while(!m_wvalid)@(negedge clk);
    if(m_wdata!==i+4096 || m_wstrb!==16'h1234 || m_wlast!==(i==length-1) || m_wid!==owner)
      $fatal(1,"buffered write changed after CPU reset");
    // Abort after DDR owns the write; no fresh CPU data is available anymore.
    if(i==0)ai_abort[0]=1;
    m_wready=1;@(negedge clk);m_wready=0;ddr_writes=ddr_writes+1;
   end
   m_bvalid=1;m_bresp=0;
   while(!m_bready)@(negedge clk);
   @(negedge clk);m_bvalid=0;cpu_done=1;
  end else begin
   for(i=0;i<length;i=i+1)begin
    m_rvalid=1;m_rdata=owner==0 ? 128'hfeed : i+8192;m_rresp=0;m_rlast=(i==length-1);
    #1;if(owner==2 && !m_rready)$fatal(1,"stalled TinyML consumer blocked DDR");
    while(!m_rready)@(negedge clk);
    @(negedge clk);m_rvalid=0;
   end
   if(owner==2)begin ai_reads=ai_reads+length;ai_read_done=1;end
  end
 end
 end
 initial begin
 wait(cpu_done && ai_read_done);snapshot=video_reads;
 wait(video_reads>=snapshot+3);
 if(ddr_writes!=256 || ai_reads!=8 || !ai_quiescent[0] || s_bvalid[1])$fatal(1,"AI drain status");
 // Return the already buffered TinyML data without needing another DDR access.
 for(integer r=0;r<8;r=r+1)begin
  @(negedge clk);while(!s_rvalid[2])@(negedge clk);
  if(s_rdata[383:256]!==r+8192 || s_rid[23:16]!==8'hd2 || s_rlast[2]!==(r==7))$fatal(1,"stored TinyML response");
  s_rready[2]=1;@(negedge clk);s_rready[2]=0;
 end
 $display("PASS CNN shared DDR: video continued across CPU abort and stalled TinyML, %0d video reads",video_reads);
 $finish;
 end
 initial begin #2000000; $display("state=%d owner=%d grants=%d video=%d cpu_sent=%d writes=%d ai_reads=%d valid=%b ready=%b buffers=%d,%d",dut.arbiter.state,owner,grants,video_reads,cpu_beats_sent,ddr_writes,ai_reads,s_avalid,s_aready,dut.ai_port[1].port.buffer.state,dut.ai_port[2].port.buffer.state);$fatal(1,"timeout");end
endmodule
