`timescale 1ns/1ps
/* V0.8 / 40: replace asynchronous-read generic line stores with synchronous
   block RAM reads, packing validity alongside each sample. Two-cycle latency.
   Previous implementation is backed up in tools/debug/before-v08/src/isp/.
   Keep the same causal 3x3 pixels and all-nine-valid semantics. */
module video_window3x3_generic #(
    parameter DATA_WIDTH = 8,
    parameter IMAGE_WIDTH = 1280,
    parameter VS_ACTIVE = 1'b0
)(
    input wire clk,
    input wire rst_n,
    input wire [DATA_WIDTH-1:0] data_i,
    input wire valid_i,
    input wire hs_i, vs_i, de_i,
    output wire [9*DATA_WIDTH-1:0] window_o,
    output reg hs_o, vs_o, de_o,
    output reg window_valid_o
);
    wire [DATA_WIDTH:0] gray_i = {valid_i,data_i};
    reg [9*(DATA_WIDTH+1)-1:0] packed_pixels;
    genvar k;
    generate for(k=0;k<9;k=k+1) begin: unpack_data
        assign window_o[k*DATA_WIDTH +: DATA_WIDTH] = packed_pixels[k*(DATA_WIDTH+1) +: DATA_WIDTH];
    end endgenerate
    reg [DATA_WIDTH:0] line1 [0:IMAGE_WIDTH-1];
    reg [DATA_WIDTH:0] line2 [0:IMAGE_WIDTH-1];
    reg [DATA_WIDTH:0] row1_q, row2_q;
    reg [11:0] x, y, x_q, y_q;
    reg [DATA_WIDTH:0] gray_q;
    reg hs_q, vs_q, de_q;
    reg [DATA_WIDTH:0] top_left2, top_left1;
    reg [DATA_WIDTH:0] mid_left2, mid_left1;
    reg [DATA_WIDTH:0] bot_left2, bot_left1;

    /* 新增：同步读 RAM；第二行缓存延迟一拍写入第一行缓存读出的旧像素。
       读、写地址分开，避免组合读 RAM，允许综合为 FPGA 块 RAM。 */
    always @(posedge clk) begin
        if (rst_n && de_i && (vs_i != VS_ACTIVE)) begin
            row1_q <= line1[x];
            row2_q <= line2[x];
            line1[x] <= gray_i;
        end
        if (rst_n && de_q && (vs_q != VS_ACTIVE))
            line2[x_q] <= row1_q;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x <= 0; y <= 0; x_q <= 0; y_q <= 0;
            gray_q <= 0;
            hs_q <= 1; vs_q <= VS_ACTIVE; de_q <= 0;
            hs_o <= 1; vs_o <= VS_ACTIVE; de_o <= 0;
            packed_pixels <= 0; window_valid_o <= 0;
            top_left2 <= 0; top_left1 <= 0;
            mid_left2 <= 0; mid_left1 <= 0;
            bot_left2 <= 0; bot_left1 <= 0;
        end else begin
            /* 新增：仅有效像素推进坐标，消隐期间保持；VS 重置帧坐标。 */
            if (vs_i == VS_ACTIVE) begin
                x <= 0; y <= 0;
            end else if (de_i) begin
                if (x == IMAGE_WIDTH-1) begin
                    x <= 0;
                    if (y != 12'hfff) y <= y + 1'b1;
                end else x <= x + 1'b1;
            end
            x_q <= x; y_q <= y; gray_q <= gray_i;
            hs_q <= hs_i; vs_q <= vs_i; de_q <= de_i;
            hs_o <= hs_q; vs_o <= vs_q; de_o <= de_q;
            window_valid_o <= de_q && (vs_q != VS_ACTIVE) && (x_q >= 2) && (y_q >= 2)
                && top_left2[DATA_WIDTH] && top_left1[DATA_WIDTH] && row2_q[DATA_WIDTH]
                && mid_left2[DATA_WIDTH] && mid_left1[DATA_WIDTH] && row1_q[DATA_WIDTH]
                && bot_left2[DATA_WIDTH] && bot_left1[DATA_WIDTH] && gray_q[DATA_WIDTH];
            if (de_q) begin
                packed_pixels <= {top_left2, top_left1, row2_q,
                             mid_left2, mid_left1, row1_q,
                             bot_left2, bot_left1, gray_q};
                top_left2 <= top_left1; top_left1 <= row2_q;
                mid_left2 <= mid_left1; mid_left1 <= row1_q;
                bot_left2 <= bot_left1; bot_left1 <= gray_q;
            end
        end
    end
endmodule
