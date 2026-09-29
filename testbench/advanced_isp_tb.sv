`timescale 1ns/1ps
/* V0.16 / 79: independent Python image oracle, all output paths/sync. */
module advanced_isp_tb;
 parameter PRESERVE=0,INVERT=0;
 reg clk=0,rst=0,hs=1,vs=0,de=0;reg [23:0] rgb=0;
 always #5 clk=~clk;
 wire [23:0] output_rgb[0:2];wire [2:0] ho,vo,do_;
 genvar i;
 generate for(i=0;i<3;i=i+1) begin: g
  video_processing #(.IMAGE_WIDTH(64)) dut(
   .clk(clk),.rst_n(rst),.ENABLE_SOBEL(1'b0),.ENABLE_MEDIAN(1'b0),
   .ENABLE_GAUSSIAN(1'b1),.ENABLE_SCHARR(i==1),.ENABLE_CANNY(i==2),.PRESERVE_EDGES(PRESERVE!=0),
   .BINARY_OUTPUT(INVERT==0),.SOBEL_THRESHOLD(12'd80),.rgb_i(rgb),.hs_i(hs),.vs_i(vs),.de_i(de),
   .rgb_o(output_rgb[i]),.hs_o(ho[i]),.vs_o(vo[i]),.de_o(do_[i]));
 end endgenerate
 integer fd,n=0,k,scan;reg ih,iv,id,eh,ev,ed;reg [23:0] inp,eg,es,ec;
 initial begin
  fd=$fopen("vectors.txt","r");if(!fd)$fatal(1,"vectors");
  repeat(4) @(negedge clk);rst=1;
  while(!$feof(fd)) begin
   scan=$fscanf(fd,"%h %h %h %h %h %h %h %h %h %h\n",ih,iv,id,inp,eh,ev,ed,eg,es,ec);
   if(scan==10) begin
    @(negedge clk);hs=ih;vs=iv;de=id;rgb=inp;@(posedge clk);#1;
    if(n>30) begin
     for(k=0;k<3;k=k+1) if({ho[k],vo[k],do_[k]}!=={eh,ev,ed})$fatal(1,"sync mode%0d cycle%0d",k,n);
     if(output_rgb[0]!==eg)$fatal(1,"gaussian cycle%0d got%h exp%h",n,output_rgb[0],eg);
     if(output_rgb[1]!==es)$fatal(1,"scharr cycle%0d got%h exp%h",n,output_rgb[1],es);
     if(output_rgb[2]!==ec)$fatal(1,"canny cycle%0d got%h exp%h",n,output_rgb[2],ec);
    end
    n=n+1;
   end
  end
  $display("PASS ADVANCED: %0d cycles all pixels and sync",n);$finish;
 end
endmodule
