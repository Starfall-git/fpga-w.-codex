`timescale 1ns/1ps
module cnn_ddr_arbiter_tb;
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
 always #5 clk=~clk;
 cnn_ddr_arbiter dut(.*);
 integer transaction,who,beat,waits;
 reg [7:0] captured;
 reg [31:0] address;
 initial begin
 #13;rst_n=1;
 s_addr={32'h6000000,32'h5000000,32'h100000};
 s_id={8'hf3,8'h92,8'h81};s_len={8'd1,8'd1,8'd1};
 s_size={3'd4,3'd4,3'd4};s_burst={2'd1,2'd1,2'd1};
 s_write=3'b010;s_avalid=3'b111;
 s_wstrb={16'hf0f0,16'h5a5a,16'h0f0f};
 s_wdata={128'h333,128'h222,128'h111};s_wvalid=3'b111;
 s_rready=3'b111;s_bready=3'b111;
 // All sources stay pending; no source can leapfrog the round-robin order.
 for(transaction=0;transaction<12;transaction=transaction+1)begin
  who=transaction%3;
  while(!m_avalid)@(negedge clk);
  address=m_addr;captured=s_id[who*8+:8];
  if(m_id!==who || m_addr!==s_addr[who*32+:32] || m_len!==1 || m_size!==4 || m_burst!==1)
    $fatal(1,"grant order or attributes %d",transaction);
  repeat(4)begin @(negedge clk);if(!m_avalid || m_addr!==address || s_aready!==0)$fatal(1,"stalled address unstable");end
  m_aready=1;#1;if(s_aready!==(3'b001<<who))$fatal(1,"ready leaked");
  @(negedge clk);m_aready=0;
  s_id[who*8+:8]=8'h00; // new request fields must not change the response ID
  if(who==1)begin
   for(beat=0;beat<2;beat=beat+1)begin
    s_wlast[who]=(beat==1);
    repeat(3)begin
     #1;if(!m_wvalid || m_wdata!==128'h222 || m_wstrb!==16'h5a5a || m_wid!==who || s_wready!==0)
       $fatal(1,"write routing/stall");
     @(negedge clk);
    end
    m_wready=1;#1;if(s_wready!==3'b010)$fatal(1,"write ready leaked");
    @(negedge clk);m_wready=0;
   end
   m_bvalid=1;m_bresp=2;
   #1;if(s_bvalid!==3'b010 || s_bid[15:8]!==captured || s_bresp[3:2]!==2 || !m_bready)$fatal(1,"B route");
   @(negedge clk);m_bvalid=0;
  end else begin
   for(beat=0;beat<2;beat=beat+1)begin
    m_rvalid=1;m_rdata=transaction*10+beat;m_rresp=beat;m_rlast=beat==1;
    s_rready[who]=0;
    repeat(3)begin
     #1;if(m_rready || s_rvalid!==(3'b001<<who) || s_rdata[who*128+:128]!==m_rdata ||
       s_rid[who*8+:8]!==captured || s_rresp[who*2+:2]!==m_rresp || s_rlast[who]!==m_rlast)
       $fatal(1,"R routing/stall");
     @(negedge clk);
    end
    s_rready[who]=1;
    @(negedge clk);m_rvalid=0;
   end
  end
  s_id[who*8+:8]=captured;
 end
 s_avalid=0;repeat(3)@(negedge clk);
 if(!idle_o || m_avalid || m_wvalid || s_rvalid || s_bvalid)$fatal(1,"not idle after drain");
 rst_n=0;@(negedge clk);
 if(m_avalid || m_wvalid || m_rready || m_bready)$fatal(1,"reset");
 $display("PASS CNN DDR arbiter: 12 round-robin transactions, exclusive routing, IDs, stalls and reset");
 $finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
