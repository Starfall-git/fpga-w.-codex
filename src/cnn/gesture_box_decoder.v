`timescale 1ns/1ps
/* v1.2 / 5: Select one spatial hand candidate and turn it into a bounded crop.
 * Q8 head order: object logit, cell dx, cell dy, normalized width, height.
 * ROI side is a multiple of64, 64..704 pixels; corners clamp inside1280x720.
 */
module gesture_box_decoder #(
    parameter THRESHOLD_FILE="src/cnn/rom_v1_2/hand_threshold.hex"
)(
    input wire clk,rst_n,start_i,valid_i,
    input wire [4:0] x_i,y_i,
    input wire [2:0] channel_i,
    input wire signed [15:0] value_i,
    output wire valid_o,
    output wire [10:0] roi_x_o,roi_y_o,
    output wire [3:0] block_o,
    output reg signed [15:0] best_score_o
);
    reg signed [15:0] threshold[0:0];
    initial $readmemh(THRESHOLD_FILE,threshold);
    reg signed [15:0] object_q,dx_q,dy_q,w_q,best_dx,best_dy,best_w,best_h;
    reg [4:0] best_x,best_y;
    function [8:0] clamp_unit(input signed [15:0] v);
        begin clamp_unit=v<0?0:(v>256?256:v[8:0]);end
    endfunction
    wire [8:0] dx=clamp_unit(best_dx),dy=clamp_unit(best_dy);
    wire [8:0] bw=clamp_unit(best_w),bh=clamp_unit(best_h);
    wire [11:0] width_px=bw*12'd5;
    wire [15:0] height_product=bh*16'd45+16'd8;
    wire [11:0] height_px=height_product>>4;
    wire [11:0] largest=width_px>height_px?width_px:height_px;
    wire [19:0] expanded=largest*20'd93+20'd4095;
    wire [7:0] blocks=expanded>>12;
    assign block_o=blocks<1?4'd1:(blocks>11?4'd11:blocks[3:0]);
    wire [10:0] side={block_o,6'b0};
    wire [16:0] cx_product=dx*17'd40+17'd128,cy_product=dy*17'd40+17'd128;
    wire [11:0] cx=best_x*12'd40+(cx_product>>8),cy=best_y*12'd40+(cy_product>>8);
    wire [11:0] left=cx>(side>>1)?cx-(side>>1):12'd0;
    wire [11:0] top=cy>(side>>1)?cy-(side>>1):12'd0;
    assign roi_x_o=left>1280-side?1280-side:left[10:0];
    assign roi_y_o=top>720-side?720-side:top[10:0];
    assign valid_o=best_score_o>=threshold[0] && width_px>=32 && height_px>=32;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            best_score_o<=-32768;object_q<=-32768;dx_q<=0;dy_q<=0;w_q<=0;
            best_dx<=0;best_dy<=0;best_w<=0;best_h<=0;best_x<=0;best_y<=0;
        end else if(start_i)begin
            best_score_o<=-32768;best_w<=0;best_h<=0;object_q<=-32768;
        end else if(valid_i)case(channel_i)
            0:object_q<=value_i;
            1:dx_q<=value_i;
            2:dy_q<=value_i;
            3:w_q<=value_i;
            4:if(object_q>best_score_o && w_q>=7 && value_i>=12 && w_q<=256 && value_i<=256)begin
                best_score_o<=object_q;best_dx<=dx_q;best_dy<=dy_q;best_w<=w_q;best_h<=value_i;
                best_x<=x_i;best_y<=y_i;
            end
        endcase
    end
endmodule
