`timescale 1ns/1ps
/* V0.9 / 46: independent image reference for four runtime output paths. */
module median_modes_tb;
  parameter WIDTH=16;
  reg clk=0,rst=0,hs=1,vs=0,de=0;
  reg [23:0] rgb=0;
  wire [23:0] raw,med,edge_rgb,both;
  wire [3:0] h,v,d;
  always #5 clk=~clk;
  video_processing #(.IMAGE_WIDTH(WIDTH)) raw_dut
    (.clk(clk),.rst_n(rst),.ENABLE_SOBEL(1'b0),.ENABLE_MEDIAN(1'b0),.BINARY_OUTPUT(1'b1),.SOBEL_THRESHOLD(12'd128),
     .rgb_i(rgb),.hs_i(hs),.vs_i(vs),.de_i(de),.rgb_o(raw),.hs_o(h[0]),.vs_o(v[0]),.de_o(d[0]));
  video_processing #(.IMAGE_WIDTH(WIDTH)) med_dut
    (.clk(clk),.rst_n(rst),.ENABLE_SOBEL(1'b0),.ENABLE_MEDIAN(1'b1),.BINARY_OUTPUT(1'b1),.SOBEL_THRESHOLD(12'd128),
     .rgb_i(rgb),.hs_i(hs),.vs_i(vs),.de_i(de),.rgb_o(med),.hs_o(h[1]),.vs_o(v[1]),.de_o(d[1]));
  video_processing #(.IMAGE_WIDTH(WIDTH)) edge_dut
    (.clk(clk),.rst_n(rst),.ENABLE_SOBEL(1'b1),.ENABLE_MEDIAN(1'b0),.BINARY_OUTPUT(1'b1),.SOBEL_THRESHOLD(12'd128),
     .rgb_i(rgb),.hs_i(hs),.vs_i(vs),.de_i(de),.rgb_o(edge_rgb),.hs_o(h[2]),.vs_o(v[2]),.de_o(d[2]));
  video_processing #(.IMAGE_WIDTH(WIDTH)) both_dut
    (.clk(clk),.rst_n(rst),.ENABLE_SOBEL(1'b1),.ENABLE_MEDIAN(1'b1),.BINARY_OUTPUT(1'b1),.SOBEL_THRESHOLD(12'd128),
     .rgb_i(rgb),.hs_i(hs),.vs_i(vs),.de_i(de),.rgb_o(both),.hs_o(h[3]),.vs_o(v[3]),.de_o(d[3]));
  integer fd,count,n=0;
  reg ri,hi,vi,di,eh,ev,ed;
  reg [23:0] pixel,er,em,ee,eb;
  reg [2047:0] filename;
  initial begin
    if(!$value$plusargs("VECTORS=%s",filename)) $fatal(1,"missing vectors");
    fd=$fopen(filename,"r"); if(!fd) $fatal(1,"cannot open vectors");
    while(!$feof(fd)) begin
      count=$fscanf(fd,"%h %h %h %h %h %h %h %h %h %h %h %h\n",ri,hi,vi,di,pixel,eh,ev,ed,er,em,ee,eb);
      if(count==12) begin
        @(negedge clk); rst=ri;hs=hi;vs=vi;de=di;rgb=pixel;
        @(posedge clk); #1;
        if(n>16) begin
          if({h[0],v[0],d[0],raw} !== {eh,ev,ed,er}) $fatal(1,"raw cycle=%0d exp=%h got=%h",n,{eh,ev,ed,er},{h[0],v[0],d[0],raw});
          if({h[1],v[1],d[1],med} !== {eh,ev,ed,em}) $fatal(1,"median cycle=%0d exp=%h got=%h",n,{eh,ev,ed,em},{h[1],v[1],d[1],med});
          if({h[2],v[2],d[2],edge_rgb} !== {eh,ev,ed,ee}) $fatal(1,"sobel cycle=%0d exp=%h got=%h",n,{eh,ev,ed,ee},{h[2],v[2],d[2],edge_rgb});
          if({h[3],v[3],d[3],both} !== {eh,ev,ed,eb}) $fatal(1,"median+sobel cycle=%0d exp=%h got=%h",n,{eh,ev,ed,eb},{h[3],v[3],d[3],both});
        end
        n=n+1;
      end else if(count!=-1) $fatal(1,"bad vector row");
    end
    $display("PASS MEDIAN MODES: %0d cycles",n); $finish;
  end
endmodule
