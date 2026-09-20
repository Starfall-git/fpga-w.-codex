`timescale 1ns/1ps
/*
2026-09-18 V0.3 新增：3x3 Sobel 梯度、绝对值幅度及阈值输出。
pixels_i 顺序为 {p00,p01,p02,p10,p11,p12,p20,p21,p22}，每项 8 bit。
Gx = 右列加权和 - 左列加权和；Gy = 下行加权和 - 上行加权和。
幅度使用 |Gx|+|Gy|，不使用开方；三段流水使 RGB/HS/VS/DE 同步延迟。
BINARY_OUTPUT=1：幅度 >= THRESHOLD 输出白色，否则黑色。
BINARY_OUTPUT=0：幅度饱和至 255，输出灰度边缘强度。
*/
module video_sobel #(
    parameter [11:0] THRESHOLD = 12'd128,
    parameter BINARY_OUTPUT = 1,
    parameter VS_ACTIVE = 1'b0
)(
    input wire clk, rst_n,
    input wire [71:0] pixels_i,
    input wire hs_i, vs_i, de_i, window_valid_i,
    output reg [23:0] rgb_o,
    output reg hs_o, vs_o, de_o
);
    wire [7:0] p00 = pixels_i[71:64], p01 = pixels_i[63:56], p02 = pixels_i[55:48];
    wire [7:0] p10 = pixels_i[47:40], p12 = pixels_i[31:24];
    wire [7:0] p20 = pixels_i[23:16], p21 = pixels_i[15:8], p22 = pixels_i[7:0];
    reg signed [10:0] gx, gy;
    wire [10:0] abs_gx = gx[10] ? (~gx + 11'd1) : gx;
    wire [10:0] abs_gy = gy[10] ? (~gy + 11'd1) : gy;
    reg [11:0] magnitude;
    reg [1:0] hs_pipe, vs_pipe, de_pipe, valid_pipe;
    wire [7:0] edge_value = BINARY_OUTPUT ?
        ((magnitude >= THRESHOLD) ? 8'hff : 8'h00) :
        ((magnitude > 12'd255) ? 8'hff : magnitude[7:0]);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gx <= 0; gy <= 0; magnitude <= 0; rgb_o <= 0;
            hs_pipe <= 2'b11; vs_pipe <= {2{VS_ACTIVE}};
            de_pipe <= 0; valid_pipe <= 0;
            hs_o <= 1; vs_o <= VS_ACTIVE; de_o <= 0;
        end else begin
            /* 新增：先扩展到 11 bit 再移位/相减，避免 8 bit 运算溢出。 */
            gx <= $signed({3'b0,p02}) + $signed({2'b0,p12,1'b0}) + $signed({3'b0,p22})
                - $signed({3'b0,p00}) - $signed({2'b0,p10,1'b0}) - $signed({3'b0,p20});
            gy <= $signed({3'b0,p20}) + $signed({2'b0,p21,1'b0}) + $signed({3'b0,p22})
                - $signed({3'b0,p00}) - $signed({2'b0,p01,1'b0}) - $signed({3'b0,p02});
            magnitude <= {1'b0,abs_gx} + {1'b0,abs_gy};
            hs_pipe <= {hs_pipe[0],hs_i}; vs_pipe <= {vs_pipe[0],vs_i};
            de_pipe <= {de_pipe[0],de_i}; valid_pipe <= {valid_pipe[0],window_valid_i};
            hs_o <= hs_pipe[1]; vs_o <= vs_pipe[1]; de_o <= de_pipe[1];
            rgb_o <= (de_pipe[1] && valid_pipe[1]) ? {3{edge_value}} : 24'd0;
        end
    end
endmodule
