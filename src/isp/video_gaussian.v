`timescale 1ns/1ps
/* V0.16 / 76: 3x3 separable-binomial weights 1 2 1 / 2 4 2 / 1 2 1.
   Range-gated option substitutes center for neighbours differing by > RANGE.
   This is a fixed-weight edge-preserving approximation, not full bilateral.
   Three clocks including window; bypass has the same temporal latency. */
module video_gaussian #(parameter IMAGE_WIDTH=1280, VS_ACTIVE=0, RANGE=16)(
 input wire clk,rst_n,enable_i,preserve_i,
 input wire [7:0] gray_i,
 input wire hs_i,vs_i,de_i,valid_i,
 output reg [7:0] gray_o,
 output wire hs_o,vs_o,de_o,
 output reg valid_o
);
 wire [71:0] win;wire wh,wv,wd,wok;
 video_window3x3 #(.IMAGE_WIDTH(IMAGE_WIDTH),.VS_ACTIVE(VS_ACTIVE)) window(
 .clk(clk),.rst_n(rst_n),.gray_i(gray_i),.pixel_valid_i(valid_i),
 .hs_i(hs_i),.vs_i(vs_i),.de_i(de_i),.pixels_o(win),
 .hs_o(wh),.vs_o(wv),.de_o(wd),.window_valid_o(wok));
 integer k,p,c,d,sum,weight;
 always @* begin
  c=win[39:32];sum=0;p=0;d=0;weight=0;
  for(k=0;k<9;k=k+1) begin
   p=(win>>(k*8)) & 255;d=p>c ? p-c : c-p;
   if(preserve_i && d>RANGE) p=c;
   weight=k==4 ? 4 : (k==1 || k==3 || k==5 || k==7) ? 2 : 1;
   sum=sum+p*weight;
  end
 end
 reg [7:0] bypass[0:1];reg [1:0] validity;
 reg ho,vo,do_;assign hs_o=ho;assign vs_o=vo;assign de_o=do_;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin bypass[0]<=0;bypass[1]<=0;validity<=0;gray_o<=0;valid_o<=0;ho<=1;vo<=VS_ACTIVE;do_<=0;end
  else begin
   bypass[0]<=gray_i;bypass[1]<=bypass[0];validity<={validity[0],valid_i};
   gray_o<=enable_i ? (wok ? (sum+8)>>4 : 0) : bypass[1];
   valid_o<=enable_i ? wok : validity[1];ho<=wh;vo<=wv;do_<=wd;
  end
 end
endmodule
