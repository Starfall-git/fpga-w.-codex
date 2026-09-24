`timescale 1ns/1ps
/*
2026-09-18 V0.3 新增：DDR 显示数据至 HDMI 之间的图像处理封装。
接口统一为 clk/rst_n + RGB888/HS/VS/DE；每拍一个像素，没有 ready/反压。
ENABLE_SOBEL=1：灰度一级 + 窗口两级 + Sobel 三级，共六级寄存器。
V0.6: ENABLE_SOBEL=0为六拍对齐的原图；=1为Sobel。BINARY_OUTPUT=1正常、=0反相。
V0.8: 增强算法及同步RAM窗口使总延迟变为15拍，原图旁路同步更新。
后续高斯滤波等模块可在本封装中串联，必须同时传递 RGB 和全部同步信号。
*/
module video_processing #(
    parameter IMAGE_WIDTH = 1280,
    /* V0.6 / 25: old ENABLE_SOBEL/SOBEL_BINARY parameters replaced by ports.
       Optional grayscale diagnostic kept separate from black/white polarity. */
    parameter GRAYSCALE_OUTPUT = 0,
    /* V0.8 / 38: removed SOBEL_BINARY parameter; use runtime BINARY_OUTPUT. */
    parameter VS_ACTIVE = 1'b0
)(
    input wire clk, rst_n,
    input wire ENABLE_SOBEL, BINARY_OUTPUT,
    /* V0.4 / 13、15：保留用户改为变量的阈值接口；输入须已同步到本clk域。 */
    input wire [11:0] SOBEL_THRESHOLD,
    input wire [23:0] rgb_i,
    input wire hs_i, vs_i, de_i,
    output wire [23:0] rgb_o,
    output wire hs_o, vs_o, de_o
);
    /* V0.6: always run Sobel; bypass is delayed by the same six registers.
       Old zero-delay generate bypass would shift HS/VS when switched at runtime. */
    wire [23:0] sobel_rgb;
    wire sobel_hs, sobel_vs, sobel_de;
    /* V0.8 / 37: was six clocks. Gray1 + input window2 + enhanced
       Sobel12 (six arithmetic/output stages + three two-clock RAM windows) =15.
       This aligns RGB with HS/VS/DE, not the spatial center of the edge kernels. */
    localparam PIPELINE_LATENCY = 15;
    reg [23:0] original [0:PIPELINE_LATENCY-1];
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin for(i=0;i<PIPELINE_LATENCY;i=i+1) original[i]<=0; end
        else begin
            original[0]<=de_i ? rgb_i : 0;
            for(i=1;i<PIPELINE_LATENCY;i=i+1) original[i]<=original[i-1];
        end
    end
    assign rgb_o=ENABLE_SOBEL ? sobel_rgb : original[PIPELINE_LATENCY-1];
    assign hs_o=sobel_hs;
    assign vs_o=sobel_vs;
    assign de_o=sobel_de;
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
        /* V0.8 / 36: restore the missing gray window. These five wires
           previously had no drivers, including HDMI HS/VS/DE through Sobel. */
        video_window3x3 #(.IMAGE_WIDTH(IMAGE_WIDTH), .VS_ACTIVE(VS_ACTIVE)) u_window (
            .clk(clk), .rst_n(rst_n), .gray_i(gray),
            .hs_i(gray_hs), .vs_i(gray_vs), .de_i(gray_de),
            .pixels_o(window_pixels), .hs_o(window_hs), .vs_o(window_vs),
            .de_o(window_de), .window_valid_o(window_valid)
        );
        /* V0.8 / 38: preserve enhanced algorithm; pass width and runtime polarity.
           Old .BINARY_OUTPUT(SOBEL_BINARY) parameter connection is removed. */
        video_sobel #(.IMAGE_WIDTH(IMAGE_WIDTH), .GRAYSCALE_OUTPUT(GRAYSCALE_OUTPUT),
                      .VS_ACTIVE(VS_ACTIVE)) u_sobel (
            .clk(clk), .rst_n(rst_n), .THRESHOLD(SOBEL_THRESHOLD),
            .BINARY_OUTPUT(BINARY_OUTPUT), .pixels_i(window_pixels),
            .hs_i(window_hs), .vs_i(window_vs), .de_i(window_de),
            .window_valid_i(window_valid), .rgb_o(sobel_rgb),
            .hs_o(sobel_hs), .vs_o(sobel_vs), .de_o(sobel_de)
        );
endmodule
