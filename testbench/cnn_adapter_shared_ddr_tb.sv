`timescale 1ns/1ps
module cnn_adapter_shared_ddr_tb;
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
 wire [2:0] adapted_avalid;
assign adapted_avalid[1:0]=s_avalid[1:0];
wire [2:0] adapted_aready;
assign s_aready[1:0]=adapted_aready[1:0];
wire [95:0] adapted_addr;
assign adapted_addr[63:0]=s_addr[63:0];
wire [23:0] adapted_id;
assign adapted_id[15:0]=s_id[15:0];
wire [23:0] adapted_len;
assign adapted_len[15:0]=s_len[15:0];
wire [8:0] adapted_size;
assign adapted_size[5:0]=s_size[5:0];
wire [5:0] adapted_burst;
assign adapted_burst[3:0]=s_burst[3:0];
wire [2:0] adapted_write;
assign adapted_write[1:0]=s_write[1:0];
wire [2:0] adapted_lock;
assign adapted_lock[1:0]=s_lock[1:0];
wire [2:0] adapted_wvalid;
assign adapted_wvalid[1:0]=s_wvalid[1:0];
wire [2:0] adapted_wready;
assign s_wready[1:0]=adapted_wready[1:0];
wire [383:0] adapted_wdata;
assign adapted_wdata[255:0]=s_wdata[255:0];
wire [47:0] adapted_wstrb;
assign adapted_wstrb[31:0]=s_wstrb[31:0];
wire [2:0] adapted_wlast;
assign adapted_wlast[1:0]=s_wlast[1:0];
wire [2:0] adapted_bvalid;
assign s_bvalid[1:0]=adapted_bvalid[1:0];
wire [2:0] adapted_bready;
assign adapted_bready[1:0]=s_bready[1:0];
wire [23:0] adapted_bid;
assign s_bid[15:0]=adapted_bid[15:0];
wire [5:0] adapted_bresp;
assign s_bresp[3:0]=adapted_bresp[3:0];
wire [2:0] adapted_rvalid;
assign s_rvalid[1:0]=adapted_rvalid[1:0];
wire [2:0] adapted_rready;
assign adapted_rready[1:0]=s_rready[1:0];
wire [383:0] adapted_rdata;
assign s_rdata[255:0]=adapted_rdata[255:0];
wire [23:0] adapted_rid;
assign s_rid[15:0]=adapted_rid[15:0];
wire [5:0] adapted_rresp;
assign s_rresp[3:0]=adapted_rresp[3:0];
wire [2:0] adapted_rlast;
assign s_rlast[1:0]=adapted_rlast[1:0];
wire awready,arready;wire [1:0] lock_full;wire [7:0] unused_wid;
assign s_aready[2]=s_write[2]?awready:arready;
assign adapted_lock[2]=|lock_full;
cnn_axi_full_to_half_duplex #(.DATA_WIDTH(128)) adapter(
.clk(clk),
.rst(!rst_n),
.io_ddr_arw_payload_lock(lock_full),
.io_ddr_w_payload_id(unused_wid),
.io_ddr_arw_valid(adapted_avalid[2+:1]),
.io_ddr_arw_ready(adapted_aready[2+:1]),
.io_ddr_arw_payload_addr(adapted_addr[64+:32]),
.io_ddr_arw_payload_id(adapted_id[16+:8]),
.io_ddr_arw_payload_len(adapted_len[16+:8]),
.io_ddr_arw_payload_size(adapted_size[6+:3]),
.io_ddr_arw_payload_burst(adapted_burst[4+:2]),
.io_ddr_arw_payload_write(adapted_write[2+:1]),
.io_ddr_w_valid(adapted_wvalid[2+:1]),
.io_ddr_w_ready(adapted_wready[2+:1]),
.io_ddr_w_payload_data(adapted_wdata[256+:128]),
.io_ddr_w_payload_strb(adapted_wstrb[32+:16]),
.io_ddr_w_payload_last(adapted_wlast[2+:1]),
.io_ddr_b_valid(adapted_bvalid[2+:1]),
.io_ddr_b_ready(adapted_bready[2+:1]),
.io_ddr_b_payload_id(adapted_bid[16+:8]),
.io_ddr_b_payload_resp(adapted_bresp[4+:2]),
.io_ddr_r_valid(adapted_rvalid[2+:1]),
.io_ddr_r_ready(adapted_rready[2+:1]),
.io_ddr_r_payload_data(adapted_rdata[256+:128]),
.io_ddr_r_payload_id(adapted_rid[16+:8]),
.io_ddr_r_payload_resp(adapted_rresp[4+:2]),
.io_ddr_r_payload_last(adapted_rlast[2+:1]),
.s_axi_awid(s_id[16+:8]),
.s_axi_awaddr(s_addr[64+:32]),
.s_axi_awlen(s_len[16+:8]),
.s_axi_awsize(s_size[6+:3]),
.s_axi_awburst(s_burst[4+:2]),
.s_axi_awlock(s_lock[2+:1]),
.s_axi_arid(s_id[16+:8]),
.s_axi_araddr(s_addr[64+:32]),
.s_axi_arlen(s_len[16+:8]),
.s_axi_arsize(s_size[6+:3]),
.s_axi_arburst(s_burst[4+:2]),
.s_axi_arlock(s_lock[2+:1]),
.s_axi_wdata(s_wdata[256+:128]),
.s_axi_wstrb(s_wstrb[32+:16]),
.s_axi_wlast(s_wlast[2+:1]),
.s_axi_wvalid(s_wvalid[2+:1]),
.s_axi_wready(s_wready[2+:1]),
.s_axi_bid(s_bid[16+:8]),
.s_axi_bresp(s_bresp[4+:2]),
.s_axi_bvalid(s_bvalid[2+:1]),
.s_axi_bready(s_bready[2+:1]),
.s_axi_rid(s_rid[16+:8]),
.s_axi_rdata(s_rdata[256+:128]),
.s_axi_rresp(s_rresp[4+:2]),
.s_axi_rlast(s_rlast[2+:1]),
.s_axi_rvalid(s_rvalid[2+:1]),
.s_axi_rready(s_rready[2+:1]),
.s_axi_awcache(4'b0),
.s_axi_awprot(3'b0),
.s_axi_awqos(4'b0),
.s_axi_awregion(4'b0),
.s_axi_arcache(4'b0),
.s_axi_arprot(3'b0),
.s_axi_arqos(4'b0),
.s_axi_arregion(4'b0),
.s_axi_awvalid(s_avalid[2] && s_write[2]),
.s_axi_arvalid(s_avalid[2] && !s_write[2]),
.s_axi_awready(awready),
.s_axi_arready(arready)
);
cnn_shared_ddr dut(.s_avalid(adapted_avalid),.s_aready(adapted_aready),.s_addr(adapted_addr),.s_id(adapted_id),.s_len(adapted_len),.s_size(adapted_size),.s_burst(adapted_burst),.s_write(adapted_write),.s_lock(adapted_lock),.s_wvalid(adapted_wvalid),.s_wready(adapted_wready),.s_wdata(adapted_wdata),.s_wstrb(adapted_wstrb),.s_wlast(adapted_wlast),.s_bvalid(adapted_bvalid),.s_bready(adapted_bready),.s_bid(adapted_bid),.s_bresp(adapted_bresp),.s_rvalid(adapted_rvalid),.s_rready(adapted_rready),.s_rdata(adapted_rdata),.s_rid(adapted_rid),.s_rresp(adapted_rresp),.s_rlast(adapted_rlast),.*);
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
 // Invalid TinyML write must return DECERR through the actual adapter.
 @(negedge clk);s_write[2]=1;s_addr[95:64]=0;s_len[23:16]=0;s_avalid[2]=1;
 do @(posedge clk);while(!s_aready[2]);
 @(negedge clk);s_avalid[2]=0;s_wvalid[2]=1;s_wlast[2]=1;s_wstrb[47:32]=16'hffff;
 do @(posedge clk);while(!s_wready[2]);
 @(negedge clk);s_wvalid[2]=0;
 wait(s_bvalid[2]);#1;if(s_bresp[5:4]!=3 || s_bid[23:16]!=8'hd2)$fatal(1,"window DECERR lost in official adapter");
 s_bready[2]=1;@(posedge clk);#1;
 $display("PASS CNN adapter/shared DDR: video continued across CPU abort and stalled TinyML, %0d video reads",video_reads);
 $finish;
 end
 initial begin #2000000; $display("state=%d owner=%d grants=%d video=%d cpu_sent=%d writes=%d ai_reads=%d valid=%b ready=%b buffers=%d,%d",dut.arbiter.state,owner,grants,video_reads,cpu_beats_sent,ddr_writes,ai_reads,s_avalid,s_aready,dut.ai_port[1].port.buffer.state,dut.ai_port[2].port.buffer.state);$fatal(1,"timeout");end
endmodule
