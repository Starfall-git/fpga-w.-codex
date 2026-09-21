`timescale 1ns/1ps
/*
2026-09-18 V0.3 新增：DDR 显示数据至 HDMI 之间的图像处理封装。
接口统一为 clk/rst_n + RGB888/HS/VS/DE；每拍一个像素，没有 ready/反压。
ENABLE_SOBEL=1：灰度一级 + 窗口两级 + Sobel 三级，共六级寄存器。
ENABLE_SOBEL=0：组合直通（零延迟），用于比较原始图像。
后续高斯滤波等模块可在本封装中串联，必须同时传递 RGB 和全部同步信号。
*/
module video_processing #(
    parameter IMAGE_WIDTH = 1280,
    parameter ENABLE_SOBEL = 1,
    parameter SOBEL_BINARY = 1,
    parameter VS_ACTIVE = 1'b0
)(
    input wire clk, rst_n,
    input wire [11:0] SOBEL_THRESHOLD,
    input wire [23:0] rgb_i,
    input wire hs_i, vs_i, de_i,
    output wire [23:0] rgb_o,
    output wire hs_o, vs_o, de_o
);
    generate if (ENABLE_SOBEL) begin: g_sobel
        /* 新增：近似灰度 Y=(R+2G+B)/4；10 bit 累加避免溢出。 */
        wire [9:0] gray_sum = {2'b0,rgb_i[23:16]} + {1'b0,rgb_i[15:8],1'b0}
                           + {2'b0,rgb_i[7:0]};
        reg [7:0] gray;
        reg gray_hs, gray_vs, gray_de;
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                gray <= 0; gray_hs <= 1; gray_vs <= VS_ACTIVE; gray_de <= 0;
            end else begin
                gray <= gray_sum[9:2];
                gray_hs <= hs_i; gray_vs <= vs_i; gray_de <= de_i;
            end
        end
        wire [71:0] window_pixels;
        wire window_hs, window_vs, window_de, window_valid;
        video_window3x3 #(.IMAGE_WIDTH(IMAGE_WIDTH), .VS_ACTIVE(VS_ACTIVE)) u_window (
            .clk(clk), .rst_n(rst_n), .gray_i(gray),
            .hs_i(gray_hs), .vs_i(gray_vs), .de_i(gray_de),
            .pixels_o(window_pixels), .hs_o(window_hs), .vs_o(window_vs),
            .de_o(window_de), .window_valid_o(window_valid)
        );
        video_sobel #(.BINARY_OUTPUT(SOBEL_BINARY),
                      .VS_ACTIVE(VS_ACTIVE)) u_sobel (
            .clk(clk), .rst_n(rst_n), .THRESHOLD(SOBEL_THRESHOLD), .pixels_i(window_pixels),
            .hs_i(window_hs), .vs_i(window_vs), .de_i(window_de), .window_valid_i(window_valid),
            .rgb_o(rgb_o), .hs_o(hs_o), .vs_o(vs_o), .de_o(de_o)
        );
    end else begin: g_bypass
        assign rgb_o = rgb_i;
        assign hs_o = hs_i;
        assign vs_o = vs_i;
        assign de_o = de_i;
    end endgenerate
endmodule
