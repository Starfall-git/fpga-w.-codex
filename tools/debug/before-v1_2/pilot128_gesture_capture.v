`timescale 1ns/1ps
/* v1.2 / 4: Full-frame 10x10 averaging or adaptive 64x64 hand ROI.
 * Command bus is held stable before ack and sampled only at a frame boundary.
 * Image RAM remains immutable until inference acknowledges the request.
 * ceil(2^24 / block^2), +half and >>24 is exact rounded division for
 * all sums 0..255*block^2 and block1..11 (verified exhaustively in Python).
 */
module gesture_capture(
    input wire pixel_clk,pixel_rst_n,frame_i,valid_i,
    input wire [7:0] gray_i,
    input wire enable_i,ack_i,detect_i,
    input wire [10:0] roi_x_i,roi_y_i,
    input wire [3:0] block_i,
    output reg request_o,detect_o,
    output reg [15:0] frame_id_o,
    input wire read_clk,
    input wire [13:0] read_addr_i,
    output reg [7:0] read_data_o
);
    reg [7:0] memory[0:9215];
    reg [15:0] columns[0:127];
    (* async_reg="true" *)reg en_meta,en_sync,ack_meta,ack_sync;
    reg [10:0] x,y,x0,y0,xend,yend;
    reg [3:0] block_size,subx,suby;
    reg [7:0] grid_width,grid_height;
    reg [6:0] col,row;
    reg [13:0] write_index;
    reg [15:0] frame_counter;
    reg frame_d,capturing;
    reg [11:0] horizontal;
    wire inside_roi=x>=x0 && x<xend && y>=y0 && y<yend;
    wire [11:0] horizontal_sum=horizontal+gray_i;
    wire [15:0] area_sum=(suby==0?16'd0:columns[col])+horizontal_sum;
    reg [24:0] reciprocal;
    always @*case(block_size)
        1:reciprocal=16777216;2:reciprocal=4194304;3:reciprocal=1864136;
        4:reciprocal=1048576;5:reciprocal=671089;6:reciprocal=466034;
        7:reciprocal=342393;8:reciprocal=262144;9:reciprocal=207127;
        10:reciprocal=167773;default:reciprocal=138655;
    endcase
    reg sum_valid,mul_valid,sum_last,mul_last;
    reg [15:0] sum_q;
    reg [24:0] factor_q;
    reg [40:0] product_q;
    reg [13:0] sum_addr,mul_addr;
    wire [40:0] rounded=product_q+41'd8388608;
    always @(posedge read_clk)read_data_o<=memory[read_addr_i];
    always @(posedge pixel_clk)begin
        if(capturing && valid_i && inside_roi && subx==block_size-1)
            columns[col]<=area_sum;
        if(mul_valid)memory[mul_addr]<=rounded[31:24];
    end
    always @(posedge pixel_clk or negedge pixel_rst_n)begin
        if(!pixel_rst_n)begin
            en_meta<=0;en_sync<=0;ack_meta<=0;ack_sync<=0;
            request_o<=0;detect_o<=1;frame_id_o<=0;frame_counter<=0;
            x<=0;y<=0;x0<=0;y0<=0;xend<=1280;yend<=720;block_size<=10;
            grid_width<=128;grid_height<=72;subx<=0;suby<=0;col<=0;row<=0;write_index<=0;
            frame_d<=0;capturing<=0;horizontal<=0;
            sum_valid<=0;mul_valid<=0;sum_last<=0;mul_last<=0;sum_q<=0;factor_q<=0;
            product_q<=0;sum_addr<=0;mul_addr<=0;
        end else begin
            en_meta<=enable_i;en_sync<=en_meta;ack_meta<=ack_i;ack_sync<=ack_meta;
            frame_d<=frame_i;
            sum_valid<=0;mul_valid<=sum_valid;
            if(sum_valid)begin product_q<=sum_q*factor_q;mul_addr<=sum_addr;mul_last<=sum_last;end
            if(mul_valid && mul_last)begin request_o<=~request_o;frame_id_o<=frame_counter;end
            if(!frame_i)begin x<=0;y<=0;capturing<=0;horizontal<=0;end
            if(frame_i && !frame_d)begin
                frame_counter<=frame_counter+1'b1;
                capturing<=en_sync && request_o==ack_sync && !sum_valid && !mul_valid;
                if(en_sync && request_o==ack_sync && !sum_valid && !mul_valid)begin
                    detect_o<=detect_i;subx<=0;suby<=0;col<=0;row<=0;write_index<=0;horizontal<=0;
                    if(detect_i)begin x0<=0;y0<=0;xend<=1280;yend<=720;block_size<=10;grid_width<=128;grid_height<=72;end
                    else begin x0<=roi_x_i;y0<=roi_y_i;xend<=roi_x_i+{block_i,6'b0};yend<=roi_y_i+{block_i,6'b0};
                        block_size<=block_i;grid_width<=64;grid_height<=64;end
                end
            end
            if(!en_sync)capturing<=0;
            if(valid_i)begin
                if(x==1279)begin x<=0;y<=y+1'b1;end else x<=x+1'b1;
                if(capturing && inside_roi)begin
                    if(subx==block_size-1)begin
                        subx<=0;horizontal<=0;
                        if(suby==block_size-1)begin
                            sum_q<=area_sum;factor_q<=reciprocal;sum_addr<=write_index;sum_valid<=1;
                            sum_last<=(row==grid_height-1 && col==grid_width-1);
                            write_index<=write_index+1'b1;
                            if(row==grid_height-1 && col==grid_width-1)capturing<=0;
                        end
                        if(col==grid_width-1)begin
                            col<=0;
                            if(suby==block_size-1)begin suby<=0;row<=row+1'b1;end else suby<=suby+1'b1;
                        end else col<=col+1'b1;
                    end else begin subx<=subx+1'b1;horizontal<=horizontal_sum;end
                end
            end
        end
    end
endmodule
