`timescale 1ns/1ps
/* v1.1 / 5: Camera-domain 512-square ROI -> 64-square 8x8 rounded area average.
 * Single immutable frame mailbox: req toggles after the final RAM write; system
 * ack releases ownership after inference. Busy frames are skipped, never stalled.
 * Coordinates count only ar0135_capture's valid image pixels (metadata removed).
 */
module gesture_roi #(
    parameter IMAGE_WIDTH=1280,ROI_X=384,ROI_Y=104
)(
    input wire pixel_clk,pixel_rst_n,frame_i,valid_i,
    input wire [7:0] gray_i,
    input wire enable_i,ack_i,
    output reg request_o,
    output reg [15:0] frame_id_o,
    input wire read_clk,
    input wire [11:0] read_addr_i,
    output reg [7:0] read_data_o
);
    reg [7:0] memory[0:4095];
    reg [15:0] columns[0:63];
    reg [10:0] x,y;
    reg [15:0] frame_counter;
    reg frame_d,capturing;
    (* async_reg="true" *)reg en_meta,en_sync,ack_meta,ack_sync;
    reg [10:0] horizontal;
    wire inside_roi=x>=ROI_X && x<ROI_X+512 && y>=ROI_Y && y<ROI_Y+512;
    wire [8:0] rx=x-ROI_X,ry=y-ROI_Y;
    wire [11:0] horizontal_sum={1'b0,horizontal}+gray_i;
    wire [15:0] area_sum=(ry[2:0]==0 ? 16'd0:columns[rx[8:3]])+horizontal_sum;
    wire [16:0] rounded_sum={1'b0,area_sum}+17'd32;
    always @(posedge read_clk)read_data_o<=memory[read_addr_i];
    always @(posedge pixel_clk)begin
        if(capturing && valid_i && inside_roi && rx[2:0]==7)begin
            columns[rx[8:3]]<=area_sum;
            if(ry[2:0]==7)memory[{ry[8:3],rx[8:3]}]<=rounded_sum[13:6];
        end
    end
    always @(posedge pixel_clk or negedge pixel_rst_n)begin
        if(!pixel_rst_n)begin
            en_meta<=0;en_sync<=0;ack_meta<=0;ack_sync<=0;
            request_o<=0;frame_id_o<=0;frame_counter<=0;
            x<=0;y<=0;frame_d<=0;capturing<=0;horizontal<=0;
        end else begin
            en_meta<=enable_i;en_sync<=en_meta;ack_meta<=ack_i;ack_sync<=ack_meta;
            frame_d<=frame_i;
            if(!frame_i)begin x<=0;y<=0;capturing<=0;horizontal<=0;end
            if(frame_i && !frame_d)begin
                frame_counter<=frame_counter+1'b1;
                capturing<=en_sync && request_o==ack_sync;
            end
            if(!en_sync)capturing<=0;
            if(valid_i)begin
                if(x==IMAGE_WIDTH-1)begin x<=0;y<=y+1'b1;end else x<=x+1'b1;
                if(capturing && inside_roi)begin
                    if(rx[2:0]==0)horizontal<=gray_i;
                    else if(rx[2:0]==7)horizontal<=0;
                    else horizontal<=horizontal_sum[10:0];
                    if(rx==511 && ry==511)begin
                        capturing<=0;request_o<=~request_o;frame_id_o<=frame_counter;
                    end
                end
            end
        end
    end
endmodule
