`timescale 1ns/1ps
/*
2026-09-18 V0.3 新增：3x3 Sobel 梯度、绝对值幅度及阈值输出。
pixels_i 顺序为 {p00,p01,p02,p10,p11,p12,p20,p21,p22}，每项 8 bit。
Gx = 右列加权和 - 左列加权和；Gy = 下行加权和 - 上行加权和。
幅度使用 |Gx|+|Gy|，不使用开方；三段流水使 RGB/HS/VS/DE 同步延迟。
BINARY_OUTPUT=1：幅度 >= THRESHOLD 输出白色，否则黑色。
V0.6 BINARY_OUTPUT=0：黑白反相；灰度诊断改用GRAYSCALE_OUTPUT参数。*/

module video_sobel #(
    parameter IMAGE_WIDTH         = 1280,
    parameter BINARY_OUTPUT       = 1'b1,
    parameter VS_ACTIVE           = 1'b0,

    // LOW_THRESHOLD = THRESHOLD >> LOW_THRESHOLD_SHIFT
    // 默认低阈值 = 高阈值 / 2
    parameter LOW_THRESHOLD_SHIFT = 1,

    // 最终孤立点过滤要求的最小邻居数量
    // 1 = 只删除真正的孤立点
    parameter MIN_NEIGHBORS       = 1
)(
    input wire clk,
    input wire rst_n,

    input wire [11:0] THRESHOLD,
    input wire [71:0] pixels_i,

    input wire hs_i,
    input wire vs_i,
    input wire de_i,
    input wire window_valid_i,

    output reg [23:0] rgb_o,
    output reg hs_o,
    output reg vs_o,
    output reg de_o
);


    /*==========================================================
     * 输入 3×3 灰度窗口
     *=========================================================*/

    wire [7:0] p00 = pixels_i[71:64];
    wire [7:0] p01 = pixels_i[63:56];
    wire [7:0] p02 = pixels_i[55:48];

    wire [7:0] p10 = pixels_i[47:40];
    wire [7:0] p11 = pixels_i[39:32];
    wire [7:0] p12 = pixels_i[31:24];

    wire [7:0] p20 = pixels_i[23:16];
    wire [7:0] p21 = pixels_i[15:8];
    wire [7:0] p22 = pixels_i[7:0];


    /*==========================================================
     * Sobel 优化
     *
     * 不直接写一长串加减，
     * 而先计算：
     *
     * left   = p00 + 2*p10 + p20
     * right  = p02 + 2*p12 + p22
     *
     * top    = p00 + 2*p01 + p02
     * bottom = p20 + 2*p21 + p22
     *
     * Gx = right  - left
     * Gy = bottom - top
     *
     * 每个加权和最大：
     *
     * 255 + 2*255 + 255 = 1020
     *
     * 因此 10 bit 足够。
     *=========================================================*/

    wire [9:0] left_sum;

    assign left_sum =
          {2'b00, p00}
        + {1'b0,  p10, 1'b0}
        + {2'b00, p20};


    wire [9:0] right_sum;

    assign right_sum =
          {2'b00, p02}
        + {1'b0,  p12, 1'b0}
        + {2'b00, p22};


    wire [9:0] top_sum;

    assign top_sum =
          {2'b00, p00}
        + {1'b0,  p01, 1'b0}
        + {2'b00, p02};


    wire [9:0] bottom_sum;

    assign bottom_sum =
          {2'b00, p20}
        + {1'b0,  p21, 1'b0}
        + {2'b00, p22};



    /*==========================================================
     * Stage 1
     *
     * Sobel Gx / Gy
     *
     * 范围：
     *
     * -1020 ~ +1020
     *
     * signed 11 bit 足够。
     *=========================================================*/

    reg signed [10:0] gx_s1;
    reg signed [10:0] gy_s1;

    reg hs_s1;
    reg vs_s1;
    reg de_s1;
    reg valid_s1;



    /*==========================================================
     * Stage 2
     *
     * Magnitude + Direction
     *=========================================================*/

    wire [10:0] abs_gx_s1 =
        gx_s1[10]
        ? (~gx_s1 + 11'd1)
        : gx_s1;


    wire [10:0] abs_gy_s1 =
        gy_s1[10]
        ? (~gy_s1 + 11'd1)
        : gy_s1;


    wire [11:0] abs_gx_ext = {1'b0, abs_gx_s1};
    wire [11:0] abs_gy_ext = {1'b0, abs_gy_s1};

    wire [11:0] abs_gx_x2 = {abs_gx_s1, 1'b0};
    wire [11:0] abs_gy_x2 = {abs_gy_s1, 1'b0};


    reg [11:0] magnitude_s2;

    /*
     * direction:
     *
     * 00 → 0°
     * 01 → 45°
     * 10 → 90°
     * 11 → 135°
     */

    reg [1:0] direction_s2;

    reg hs_s2;
    reg vs_s2;
    reg de_s2;
    reg valid_s2;



    /*==========================================================
     * Gradient Window
     *
     * 每个像素：
     *
     * 2 bit direction
     * +
     * 12 bit magnitude
     *
     * = 14 bit
     *
     * 3×3：
     *
     * 14 × 9 = 126 bit
     *=========================================================*/

    wire [125:0] grad_window;

    wire grad_hs;
    wire grad_vs;
    wire grad_de;
    wire grad_window_valid;


    video_window3x3_generic #(
        .IMAGE_WIDTH (IMAGE_WIDTH),
        .DATA_WIDTH  (14),
        .VS_ACTIVE   (VS_ACTIVE)
    )
    u_grad_window (
        .clk            (clk),
        .rst_n          (rst_n),

        .data_i         ({
                            direction_s2,
                            magnitude_s2
                         }),

        .valid_i        (valid_s2),

        .hs_i           (hs_s2),
        .vs_i           (vs_s2),
        .de_i           (de_s2),

        .window_o       (grad_window),

        .hs_o           (grad_hs),
        .vs_o           (grad_vs),
        .de_o           (grad_de),

        .window_valid_o (grad_window_valid)
    );


    /*
     * Gradient 3×3
     */

    wire [13:0] g00 = grad_window[125:112];
    wire [13:0] g01 = grad_window[111:98];
    wire [13:0] g02 = grad_window[97:84];

    wire [13:0] g10 = grad_window[83:70];
    wire [13:0] g11 = grad_window[69:56];
    wire [13:0] g12 = grad_window[55:42];

    wire [13:0] g20 = grad_window[41:28];
    wire [13:0] g21 = grad_window[27:14];
    wire [13:0] g22 = grad_window[13:0];


    wire [1:0]  center_direction = g11[13:12];
    wire [11:0] center_magnitude = g11[11:0];


    /*==========================================================
     * NMS
     *
     * 根据方向选择两个邻居。
     *=========================================================*/

    reg [11:0] nms_neighbor1;
    reg [11:0] nms_neighbor2;


    always @(*) begin

        case (center_direction)

            /*
             * 0°
             *
             * g10 ← g11 → g12
             */

            2'b00: begin

                nms_neighbor1 = g10[11:0];
                nms_neighbor2 = g12[11:0];

            end


            /*
             * 45°
             *
             * g00
             *    \
             *     g11
             *        \
             *         g22
             */

            2'b01: begin

                nms_neighbor1 = g00[11:0];
                nms_neighbor2 = g22[11:0];

            end


            /*
             * 90°
             */

            2'b10: begin

                nms_neighbor1 = g01[11:0];
                nms_neighbor2 = g21[11:0];

            end


            /*
             * 135°
             */

            default: begin

                nms_neighbor1 = g02[11:0];
                nms_neighbor2 = g20[11:0];

            end

        endcase

    end



    /*==========================================================
     * Stage 3
     *
     * NMS 输出
     *=========================================================*/

    reg [11:0] nms_magnitude_s3;

    reg hs_s3;
    reg vs_s3;
    reg de_s3;
    reg valid_s3;



    /*==========================================================
     * Double Threshold
     *
     * THRESHOLD 作为 HIGH_THRESHOLD
     *
     * 默认：
     *
     * LOW_THRESHOLD = HIGH_THRESHOLD / 2
     *=========================================================*/

    wire [11:0] low_threshold;

    assign low_threshold =
        THRESHOLD >> LOW_THRESHOLD_SHIFT;


    /*
     * Edge State:
     *
     * 00 = 非边缘
     * 01 = Weak Edge
     * 10 = Strong Edge
     */

    reg [1:0] edge_state_s4;

    reg [11:0] nms_magnitude_s4;

    reg hs_s4;
    reg vs_s4;
    reg de_s4;
    reg valid_s4;



    /*==========================================================
     * State Window
     *
     * 每个像素：
     *
     * edge_state : 2 bit
     * magnitude  : 12 bit
     *
     * 共 14 bit
     *=========================================================*/

    wire [125:0] state_window;

    wire state_hs;
    wire state_vs;
    wire state_de;
    wire state_window_valid;


    video_window3x3_generic #(
        .IMAGE_WIDTH (IMAGE_WIDTH),
        .DATA_WIDTH  (14),
        .VS_ACTIVE   (VS_ACTIVE)
    )
    u_state_window (
        .clk            (clk),
        .rst_n          (rst_n),

        .data_i         ({
                            edge_state_s4,
                            nms_magnitude_s4
                         }),

        .valid_i        (valid_s4),

        .hs_i           (hs_s4),
        .vs_i           (vs_s4),
        .de_i           (de_s4),

        .window_o       (state_window),

        .hs_o           (state_hs),
        .vs_o           (state_vs),
        .de_o           (state_de),

        .window_valid_o (state_window_valid)
    );


    wire [13:0] s00 = state_window[125:112];
    wire [13:0] s01 = state_window[111:98];
    wire [13:0] s02 = state_window[97:84];

    wire [13:0] s10 = state_window[83:70];
    wire [13:0] s11 = state_window[69:56];
    wire [13:0] s12 = state_window[55:42];

    wire [13:0] s20 = state_window[41:28];
    wire [13:0] s21 = state_window[27:14];
    wire [13:0] s22 = state_window[13:0];


    wire [1:0] center_state =
        s11[13:12];

    wire [11:0] center_nms_magnitude =
        s11[11:0];


    /*==========================================================
     * Local Weak-Strong Connection
     *
     * Strong:
     *     一定保留
     *
     * Weak:
     *     8邻域存在 Strong 才保留
     *
     * 注意：
     * 这里只检查一层邻域。
     * 不做递归传播。
     *=========================================================*/

    wire neighbor_has_strong;

    assign neighbor_has_strong =

           (s00[13:12] == 2'b10)
        || (s01[13:12] == 2'b10)
        || (s02[13:12] == 2'b10)

        || (s10[13:12] == 2'b10)
        || (s12[13:12] == 2'b10)

        || (s20[13:12] == 2'b10)
        || (s21[13:12] == 2'b10)
        || (s22[13:12] == 2'b10);


    wire connected_edge;

    assign connected_edge =

           (center_state == 2'b10)

        || (
            (center_state == 2'b01)
            && neighbor_has_strong
        );



    /*==========================================================
     * Stage 5
     *
     * 保存：
     *
     * connected edge : 1 bit
     * magnitude      : 12 bit
     *
     * 共 13 bit
     *=========================================================*/

    reg [12:0] connected_word_s5;

    reg hs_s5;
    reg vs_s5;
    reg de_s5;
    reg valid_s5;



    /*==========================================================
     * Binary Edge Window
     *
     * 用于孤立点过滤。
     *=========================================================*/

    wire [116:0] edge_window;

    wire edge_hs;
    wire edge_vs;
    wire edge_de;
    wire edge_window_valid;


    video_window3x3_generic #(
        .IMAGE_WIDTH (IMAGE_WIDTH),
        .DATA_WIDTH  (13),
        .VS_ACTIVE   (VS_ACTIVE)
    )
    u_edge_window (
        .clk            (clk),
        .rst_n          (rst_n),

        .data_i         (connected_word_s5),
        .valid_i        (valid_s5),

        .hs_i           (hs_s5),
        .vs_i           (vs_s5),
        .de_i           (de_s5),

        .window_o       (edge_window),

        .hs_o           (edge_hs),
        .vs_o           (edge_vs),
        .de_o           (edge_de),

        .window_valid_o (edge_window_valid)
    );


    /*
     * 每个 word:
     *
     * bit 12    : edge
     * bit 11:0  : NMS magnitude
     */

    wire [12:0] e00 = edge_window[116:104];
    wire [12:0] e01 = edge_window[103:91];
    wire [12:0] e02 = edge_window[90:78];

    wire [12:0] e10 = edge_window[77:65];
    wire [12:0] e11 = edge_window[64:52];
    wire [12:0] e12 = edge_window[51:39];

    wire [12:0] e20 = edge_window[38:26];
    wire [12:0] e21 = edge_window[25:13];
    wire [12:0] e22 = edge_window[12:0];


    wire center_edge =
        e11[12];

    wire [11:0] final_magnitude =
        e11[11:0];


    /*==========================================================
     * 8邻域边缘数量
     *=========================================================*/

    wire [3:0] neighbor_count;

    assign neighbor_count =

          {3'd0, e00[12]}
        + {3'd0, e01[12]}
        + {3'd0, e02[12]}

        + {3'd0, e10[12]}
        + {3'd0, e12[12]}

        + {3'd0, e20[12]}
        + {3'd0, e21[12]}
        + {3'd0, e22[12]};


    /*
     * 最终边缘：
     *
     * 中心必须本来就是边缘，
     * 并且附近至少 MIN_NEIGHBORS 个边缘。
     */

    wire final_edge;

    assign final_edge =

           center_edge
        && (neighbor_count >= MIN_NEIGHBORS);



    /*==========================================================
     * 非二值模式的 NMS 梯度输出
     *=========================================================*/

    wire [7:0] gradient_gray;

    assign gradient_gray =
        (final_magnitude > 12'd255)
        ? 8'hff
        : final_magnitude[7:0];



    /*==========================================================
     * Pipeline
     *=========================================================*/

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            /*
             * Stage 1
             */

            gx_s1 <= 11'sd0;
            gy_s1 <= 11'sd0;

            hs_s1    <= 1'b1;
            vs_s1    <= ~VS_ACTIVE;
            de_s1    <= 1'b0;
            valid_s1 <= 1'b0;


            /*
             * Stage 2
             */

            magnitude_s2 <= 12'd0;
            direction_s2 <= 2'b00;

            hs_s2    <= 1'b1;
            vs_s2    <= ~VS_ACTIVE;
            de_s2    <= 1'b0;
            valid_s2 <= 1'b0;


            /*
             * Stage 3
             */

            nms_magnitude_s3 <= 12'd0;

            hs_s3    <= 1'b1;
            vs_s3    <= ~VS_ACTIVE;
            de_s3    <= 1'b0;
            valid_s3 <= 1'b0;


            /*
             * Stage 4
             */

            edge_state_s4     <= 2'b00;
            nms_magnitude_s4  <= 12'd0;

            hs_s4    <= 1'b1;
            vs_s4    <= ~VS_ACTIVE;
            de_s4    <= 1'b0;
            valid_s4 <= 1'b0;


            /*
             * Stage 5
             */

            connected_word_s5 <= 13'd0;

            hs_s5    <= 1'b1;
            vs_s5    <= ~VS_ACTIVE;
            de_s5    <= 1'b0;
            valid_s5 <= 1'b0;


            /*
             * Output
             */

            rgb_o <= 24'd0;

            hs_o <= 1'b1;
            vs_o <= ~VS_ACTIVE;
            de_o <= 1'b0;

        end

        else begin

            /*==================================================
             * Stage 1
             * Sobel
             *=================================================*/

            gx_s1 <=
                $signed({1'b0, right_sum})
                -
                $signed({1'b0, left_sum});


            gy_s1 <=
                $signed({1'b0, bottom_sum})
                -
                $signed({1'b0, top_sum});


            hs_s1    <= hs_i;
            vs_s1    <= vs_i;
            de_s1    <= de_i;
            valid_s1 <= window_valid_i;



            /*==================================================
             * Stage 2
             * Magnitude
             *=================================================*/

            magnitude_s2 <=
                abs_gx_ext
                +
                abs_gy_ext;


            /*
             * Direction Quantization
             *
             * 用 0.5 和 2 作为简单边界。
             *
             * |Gy| <= |Gx|/2
             * → 0°
             */

            if (abs_gy_x2 <= abs_gx_ext) begin

                direction_s2 <= 2'b00;

            end


            /*
             * |Gx| <= |Gy|/2
             * → 90°
             */

            else if (abs_gx_x2 <= abs_gy_ext) begin

                direction_s2 <= 2'b10;

            end


            /*
             * 剩余为斜边。
             */

            else begin

                /*
                 * Gx / Gy 同号
                 * → 45°
                 */

                if (gx_s1[10] == gy_s1[10])

                    direction_s2 <= 2'b01;


                /*
                 * Gx / Gy 异号
                 * → 135°
                 */

                else

                    direction_s2 <= 2'b11;

            end


            hs_s2    <= hs_s1;
            vs_s2    <= vs_s1;
            de_s2    <= de_s1;
            valid_s2 <= valid_s1;



            /*==================================================
             * Stage 3
             * NMS
             *=================================================*/

            if (
                grad_window_valid
                &&
                (center_magnitude >= nms_neighbor1)
                &&
                (center_magnitude >= nms_neighbor2)
            )
            begin

                nms_magnitude_s3 <= center_magnitude;

            end

            else begin

                nms_magnitude_s3 <= 12'd0;

            end


            hs_s3    <= grad_hs;
            vs_s3    <= grad_vs;
            de_s3    <= grad_de;
            valid_s3 <= grad_window_valid;



            /*==================================================
             * Stage 4
             * Double Threshold
             *=================================================*/

            nms_magnitude_s4 <=
                nms_magnitude_s3;


            if (!valid_s3) begin

                edge_state_s4 <= 2'b00;

            end

            else if (
                nms_magnitude_s3 >= THRESHOLD
            )
            begin

                /*
                 * Strong Edge
                 */

                edge_state_s4 <= 2'b10;

            end

            else if (
                nms_magnitude_s3 >= low_threshold
            )
            begin

                /*
                 * Weak Edge
                 */

                edge_state_s4 <= 2'b01;

            end

            else begin

                edge_state_s4 <= 2'b00;

            end


            hs_s4    <= hs_s3;
            vs_s4    <= vs_s3;
            de_s4    <= de_s3;
            valid_s4 <= valid_s3;



            /*==================================================
             * Stage 5
             * Local Weak-Strong Connection
             *=================================================*/

            connected_word_s5 <= {
                connected_edge,
                center_nms_magnitude
            };


            hs_s5    <= state_hs;
            vs_s5    <= state_vs;
            de_s5    <= state_de;
            valid_s5 <= state_window_valid;



            /*==================================================
             * Output
             *=================================================*/

            hs_o <= edge_hs;
            vs_o <= edge_vs;
            de_o <= edge_de;


            if (
                edge_de
                &&
                edge_window_valid
            )
            begin

                /*
                 * Binary Output
                 */

                if (BINARY_OUTPUT) begin

                    rgb_o <=
                        final_edge
                        ? 24'hffffff
                        : 24'h000000;

                end

                /*
                 * Gradient Output
                 *
                 * 输出经过 NMS 后的梯度。
                 */

                else begin

                    rgb_o <= {
                        gradient_gray,
                        gradient_gray,
                        gradient_gray
                    };

                end

            end

            else begin

                rgb_o <= 24'h000000;

            end

        end

    end


endmodule