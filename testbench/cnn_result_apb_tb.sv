`timescale 1ns/1ps
module cnn_result_apb_tb;
 reg clk=0,pclk=0,rst=0,prst=0;
 always #7 clk=~clk;
 always #5 pclk=~pclk;
 reg [15:0] addr=0;
 reg sel=0,en=0,wr=0;
 reg [31:0] wdata=0;
 wire ready,err,send,valid,mail_ready;
 wire [31:0] rdata,frame;
 wire [1:0] cls;
 wire [11:0] x0,y0,x1,y1;
 reg boundary=0;
 wire [82:0] packet;
 wire commit;
 integer commits=0;
 cnn_result_apb dut(.PCLK(clk),.PRESETn(rst),.PADDR(addr),.PSEL(sel),
 .PENABLE(en),.PWRITE(wr),.PWDATA(wdata),.PREADY(ready),.PSLVERROR(err),
 .PRDATA(rdata),.control_status(2'b00),.result_ready(mail_ready),.result_send(send),.result_valid(valid),
 .result_class(cls),.roi_x0(x0),.roi_y0(y0),.roi_x1(x1),.roi_y1(y1),.source_frame(frame));
 cnn_result_mailbox mb(.src_clk(clk),.src_rst_n(rst),.src_valid(send),
 .src_data({frame,valid,cls,x0,y0,x1,y1}),.src_ready(mail_ready),
 .dst_clk(pclk),.dst_rst_n(prst),.frame_boundary(boundary),.dst_data(packet),.dst_commit(commit));
 always @(posedge pclk) if(commit) commits=commits+1;
 task bus(input bit write_op,input [15:0] a,input [31:0] d,input bit expected_error);
 begin
 @(negedge clk); sel=1; en=0; wr=write_op; addr=a; wdata=d;
 @(posedge clk); #1; if(send) $fatal(1,"APB setup caused publication");
 @(negedge clk); en=1;
 #1; if(!ready || err!==expected_error) $fatal(1,"APB response %h err=%b",a,err);
 @(posedge clk); #1;
 @(negedge clk); sel=0; en=0;
 end endtask
 task check_read(input [15:0] a,input [31:0] expected);
 begin
 @(negedge clk); sel=1; en=0; wr=0; addr=a;
 @(negedge clk); en=1; #1;
 if(err || !ready || rdata!==expected) $fatal(1,"read %h got %h expected %h",a,rdata,expected);
 @(negedge clk); sel=0; en=0;
 end endtask
 task latch_frame;
 begin
 repeat(5) @(negedge pclk);
 boundary=1; @(negedge pclk); boundary=0;
 repeat(5) @(negedge clk);
 end endtask
 initial begin
 #2; rst=0; prst=0;
 repeat(4) @(negedge clk); rst=1; prst=1;
 repeat(5) @(negedge clk);
 check_read(0,32'h47535431); check_read(4,1);
 bus(1,8,42,0); bus(1,12,32'h00030002,0);
 bus(1,16,32'h000b000e,0); bus(1,24,5,0);
 bus(1,20,1,0); check_read(28,1);
 // Shadow writes must not tear the pending frame, and busy never stalls APB.
 bus(1,8,99,0); bus(1,12,32'h00010001,0); bus(1,24,3,0);
 bus(1,20,1,1); check_read(4,2); check_read(28,1);
 repeat(10) @(negedge pclk);
 if(commits!=0) $fatal(1,"published outside boundary");
 latch_frame();
 if(packet!=={32'd42,1'b1,2'd2,12'd2,12'd3,12'd14,12'd11} || commits!=1)
 $fatal(1,"pending packet torn or duplicated");
 check_read(4,3); bus(1,32,1,0); check_read(4,1);
 bus(1,20,1,0); latch_frame();
 if(packet!=={32'd99,1'b1,2'd1,12'd1,12'd1,12'd14,12'd11} || commits!=2)
 $fatal(1,"second packet wrong");
 bus(1,20,2,1); bus(1,0,0,1); bus(0,16'h1004,0,1); bus(1,9,1,1);
 check_read(28,2);
 // Clear result is a real publication, even though valid is zero.
 bus(1,24,0,0); bus(1,20,1,0); latch_frame();
 if(packet[50]!==0 || commits!=3) $fatal(1,"invalidate missing");
 @(negedge clk); rst=0;
 repeat(3) @(negedge clk); rst=1;
 repeat(5) @(negedge clk);
 check_read(28,0); check_read(8,0); check_read(4,1);
 $display("PASS CNN result APB: atomic frames, busy, errors, invalidate, reset");
 $finish;
 end
 initial begin #100000; $fatal(1,"timeout"); end
endmodule
