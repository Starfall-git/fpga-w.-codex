`timescale 1ns/1ps
/* V0.16 / 77: normalized Scharr L1 magnitude, quantized gradient direction,
   NMS, high/low=THRESHOLD/max(THRESHOLD/2,1), two local hysteresis rounds.
   Finite (two-hop) streaming hysteresis is not global recursive Canny.
   V0.19: Scharr RGB latency=3 clocks; Canny RGB=23 clocks from window input.
   Valid bits exclude incomplete windows; magnitude carries 12 bits. */
module video_scharr_canny #(parameter IMAGE_WIDTH=1280,VS_ACTIVE=0)(
 input wire clk,rst_n,BINARY_OUTPUT,
 /* V0.19 / 90-91: approximate L2 improves angular uniformity; selectable
    six-hop hysteresis and isolated-seed rejection. Not global Canny. */
 input wire [15:0] tuning_i,
 input wire [11:0] THRESHOLD,
 input wire [71:0] pixels_i,
 input wire hs_i,vs_i,de_i,window_valid_i,
 output reg [23:0] scharr_o,
 output wire [23:0] canny_o,
 output wire hs_o,vs_o,de_o
);
 integer a,b,c,d,f,g,h,i;
 reg signed [12:0] gx,gy;
 wire [12:0] ax=gx[12] ? -gx : gx, ay=gy[12] ? -gy : gy;
 wire [13:0] total={1'b0,ax}+{1'b0,ay};
 wire [12:0] hi=ax>ay ? ax : ay, lo=ax>ay ? ay : ax;
 wire [16:0] norm={4'd0,hi}+(({4'd0,lo}*3)>>3);
 reg [13:0] magnitude_dir;
 reg [1:0] hp,vp,dp,validp;
 wire [11:0] magnitude=magnitude_dir[13:2];
 wire [11:0] excess=magnitude>THRESHOLD ? magnitude-THRESHOLD : 0;
 wire [7:0] strength=excess>510 ? 255 : excess[8:1];
 wire [7:0] visible=BINARY_OUTPUT ? strength : ~strength;
 always @* begin
  a=pixels_i[71:64];b=pixels_i[63:56];c=pixels_i[55:48];
  d=pixels_i[47:40];f=pixels_i[31:24];g=pixels_i[23:16];h=pixels_i[15:8];i=pixels_i[7:0];
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin gx<=0;gy<=0;magnitude_dir<=0;hp<=3;vp<={2{VS_ACTIVE}};dp<=0;validp<=0;scharr_o<=0;end
  else begin
   gx<=3*(c-a)+10*(f-d)+3*(i-g);
   gy<=3*(g-a)+10*(h-b)+3*(i-c);
   magnitude_dir[13:2]<=tuning_i[1] ? norm>>2 : total>>2;
   /* tan(22.5deg) ~= 106/256, preserving four normal directions. */
   if(ay*256<=ax*106) magnitude_dir[1:0]<=0;
   else if(ax*256<=ay*106) magnitude_dir[1:0]<=2;
   else magnitude_dir[1:0]<=gx[12]==gy[12] ? 1 : 3;
   hp<={hp[0],hs_i};vp<={vp[0],vs_i};dp<={dp[0],de_i};validp<={validp[0],window_valid_i};
   scharr_o<=dp[1] ? (validp[1] ? {3{visible}} : (BINARY_OUTPUT ? 24'd0 : 24'hffffff)) : 0;
  end
 end
 wire [125:0] mw;wire mh,mv,md,mvalid;
 video_window3x3 #(.IMAGE_WIDTH(IMAGE_WIDTH),.DATA_WIDTH(14),.VS_ACTIVE(VS_ACTIVE)) mag_window(
 .clk(clk),.rst_n(rst_n),.gray_i(magnitude_dir),.pixel_valid_i(validp[1]),
 .hs_i(hp[1]),.vs_i(vp[1]),.de_i(dp[1]),.pixels_o(mw),.hs_o(mh),.vs_o(mv),.de_o(md),.window_valid_o(mvalid));
 wire [13:0] mc=mw[69:56];
 reg [11:0] n1,n2;
 always @* begin
  case(mc[1:0])
   0:begin n1=mw[83:72];n2=mw[55:44];end
   1:begin n1=mw[125:114];n2=mw[13:2];end
   2:begin n1=mw[111:100];n2=mw[27:16];end
   default:begin n1=mw[97:86];n2=mw[41:30];end
  endcase
 end
 wire [11:0] high_t=THRESHOLD==0 ? 12'd1 : THRESHOLD;
 /* V0.19: pipeline configuration arithmetic during blanking to keep the
    percentage multiplier/divider off the gradient/NMS critical path. */
 reg [19:0] low_product;reg [11:0] low_t;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin low_product<=0;low_t<=1;end
  else begin low_product<=high_t*tuning_i[15:8];low_t<=low_product<100 ? 12'd1 : low_product/100;end
 end
 reg [1:0] label;reg nh,nv,nd,nvalid;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin label<=0;nh<=1;nv<=VS_ACTIVE;nd<=0;nvalid<=0;end
  else begin
   nh<=mh;nv<=mv;nd<=md;nvalid<=mvalid;
   if(mvalid && mc[13:2]>=n1 && mc[13:2]>n2 && mc[13:2]>=low_t)
    label<=mc[13:2]>=high_t ? 2 : 1;
   else label<=0;
  end
 end
 wire [1:0] stage_label[0:6];wire [6:0] sh,sv,sd,sk;
 assign stage_label[0]=label;assign sh[0]=nh;assign sv[0]=nv;assign sd[0]=nd;assign sk[0]=nvalid;
 genvar stage;
 generate for(stage=0;stage<6;stage=stage+1) begin: g_link
  wire [17:0] labels;wire lh,lv,ld,lk;
  video_window3x3 #(.IMAGE_WIDTH(IMAGE_WIDTH),.DATA_WIDTH(2),.VS_ACTIVE(VS_ACTIVE)) label_window(
   .clk(clk),.rst_n(rst_n),.gray_i(stage_label[stage]),.pixel_valid_i(sk[stage]),
   .hs_i(sh[stage]),.vs_i(sv[stage]),.de_i(sd[stage]),.pixels_o(labels),
   .hs_o(lh),.vs_o(lv),.de_o(ld),.window_valid_o(lk));
  integer j;reg nearby,support;reg [1:0] promoted;reg ph,pv,pd,pk;
  always @* begin
   nearby=0;support=0;
   for(j=0;j<9;j=j+1) if(j!=4) begin
    if(labels[j*2+:2]==2) nearby=1;
    if(labels[j*2+:2]!=0) support=1;
   end
  end
  always @(posedge clk or negedge rst_n) begin
   if(!rst_n) begin promoted<=0;ph<=1;pv<=VS_ACTIVE;pd<=0;pk<=0;end
   else begin
    /* V0.19: never invent zero-gradient pixels to bridge a gap. Extended
       stages carry center labels when disabled, keeping fixed output timing. */
    if(!lk) promoted<=0;
    else if(stage==0 && tuning_i[3] && !support) promoted<=0;
    else if(stage>=2 && !tuning_i[2]) promoted<=labels[9:8];
    else promoted<=labels[9:8]==2 || (labels[9:8]==1 && nearby) ? 2 : labels[9:8];
    ph<=lh;pv<=lv;pd<=ld;pk<=lk;
   end
  end
  assign stage_label[stage+1]=promoted;assign sh[stage+1]=ph;assign sv[stage+1]=pv;
  assign sd[stage+1]=pd;assign sk[stage+1]=pk;
 end endgenerate
 wire hit=sk[6] && stage_label[6]==2;
 assign canny_o=sd[6] ? ((hit==BINARY_OUTPUT) ? 24'hffffff : 24'd0) : 0;
 assign hs_o=sh[6];assign vs_o=sv[6];assign de_o=sd[6];
endmodule
