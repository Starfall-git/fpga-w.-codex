`timescale 1ns/1ps
/*
2026-09-18 V0.3 新增：两个灰度行缓存和 3x3 滑动窗口。
每个 DE=1 的时钟接收一个像素；一行必须恰好 IMAGE_WIDTH 个有效像素。
HS/VS/DE 每拍流水，不能只在 DE=1 时延迟。同步信号延迟两级寄存器。
窗口覆盖 (x-2,y-2)..(x,y)，window_valid_o 屏蔽每帧前两行和每行前两列。
RAM 不复位，依靠窗口有效标志阻止旧帧/未初始化数据进入结果。
要求 IMAGE_WIDTH >= 3，帧之间有有效 VS 脉冲，默认 VS 低有效。
*/
module video_window3x3 #(
    parameter IMAGE_WIDTH = 1280,
    parameter VS_ACTIVE = 1'b0
)(
    input wire clk,
    input wire rst_n,
    input wire [7:0] gray_i,
    input wire hs_i, vs_i, de_i,
    output reg [71:0] pixels_o,
    output reg hs_o, vs_o, de_o,
    output reg window_valid_o
);
    reg [7:0] line1 [0:IMAGE_WIDTH-1];
    reg [7:0] line2 [0:IMAGE_WIDTH-1];
    reg [7:0] row1_q, row2_q;
    reg [11:0] x, y, x_q, y_q;
    reg [7:0] gray_q;
    reg hs_q, vs_q, de_q;
    reg [7:0] top_left2, top_left1;
    reg [7:0] mid_left2, mid_left1;
    reg [7:0] bot_left2, bot_left1;

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
            pixels_o <= 0; window_valid_o <= 0;
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
            window_valid_o <= de_q && (vs_q != VS_ACTIVE) && (x_q >= 2) && (y_q >= 2);
            if (de_q) begin
                pixels_o <= {top_left2, top_left1, row2_q,
                             mid_left2, mid_left1, row1_q,
                             bot_left2, bot_left1, gray_q};
                top_left2 <= top_left1; top_left1 <= row2_q;
                mid_left2 <= mid_left1; mid_left1 <= row1_q;
                bot_left2 <= bot_left1; bot_left1 <= gray_q;
            end
        end
    end
endmodule
