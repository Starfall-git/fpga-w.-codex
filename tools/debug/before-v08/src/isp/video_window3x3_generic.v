/*==============================================================
 *
 * Generic Streaming 3×3 Window
 *
 * DATA_WIDTH 可配置：
 *
 * 8  bit : Gray
 * 14 bit : Direction + Magnitude
 * 13 bit : Edge + Magnitude
 *
 * 注意：
 *
 * 这里使用两个 line buffer。
 *
 * Window:
 *
 * d00 d01 d02
 * d10 d11 d12
 * d20 d21 d22
 *
 * 当前输入 data_i 位于右下角 d22。
 *
 *=============================================================*/

module video_window3x3_generic #(

    parameter IMAGE_WIDTH = 1280,
    parameter DATA_WIDTH  = 8,
    parameter VS_ACTIVE   = 1'b0

)(
    input  wire                      clk,
    input  wire                      rst_n,

    input  wire [DATA_WIDTH-1:0]     data_i,
    input  wire                      valid_i,

    input  wire                      hs_i,
    input  wire                      vs_i,
    input  wire                      de_i,

    output reg [DATA_WIDTH*9-1:0]    window_o,

    output reg                       hs_o,
    output reg                       vs_o,
    output reg                       de_o,

    output reg                       window_valid_o
);


    /*
     * 两级行缓存。
     *
     * 注意：
     * 不在 reset 中清整个 RAM，
     * 否则很难推断 Block RAM。
     */

    reg [DATA_WIDTH-1:0]
        line1 [0:IMAGE_WIDTH-1];

    reg [DATA_WIDTH-1:0]
        line2 [0:IMAGE_WIDTH-1];


    /*
     * 对应 valid 的行缓存。
     */

    reg line1_valid [0:IMAGE_WIDTH-1];
    reg line2_valid [0:IMAGE_WIDTH-1];


    integer x_count;
    integer line_count;


    /*
     * 当前三行各保存前两个像素。
     */

    reg [DATA_WIDTH-1:0] top0;
    reg [DATA_WIDTH-1:0] top1;

    reg [DATA_WIDTH-1:0] mid0;
    reg [DATA_WIDTH-1:0] mid1;

    reg [DATA_WIDTH-1:0] bot0;
    reg [DATA_WIDTH-1:0] bot1;


    reg top0_valid;
    reg top1_valid;

    reg mid0_valid;
    reg mid1_valid;

    reg bot0_valid;
    reg bot1_valid;


    reg vs_d;
    reg de_d;


    wire frame_start;

    assign frame_start =
           (vs_i == VS_ACTIVE)
        && (vs_d != VS_ACTIVE);



    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            x_count    <= 0;
            line_count <= 0;

            top0 <= 0;
            top1 <= 0;

            mid0 <= 0;
            mid1 <= 0;

            bot0 <= 0;
            bot1 <= 0;


            top0_valid <= 1'b0;
            top1_valid <= 1'b0;

            mid0_valid <= 1'b0;
            mid1_valid <= 1'b0;

            bot0_valid <= 1'b0;
            bot1_valid <= 1'b0;


            window_o <= 0;

            window_valid_o <= 1'b0;


            hs_o <= 1'b1;
            vs_o <= ~VS_ACTIVE;
            de_o <= 1'b0;


            vs_d <= ~VS_ACTIVE;
            de_d <= 1'b0;

        end

        else begin

            vs_d <= vs_i;
            de_d <= de_i;


            /*
             * 同步信号继续向后传。
             */

            hs_o <= hs_i;
            vs_o <= vs_i;
            de_o <= de_i;


            /*
             * 新帧开始。
             */

            if (frame_start) begin

                x_count    <= 0;
                line_count <= 0;

                top0 <= 0;
                top1 <= 0;

                mid0 <= 0;
                mid1 <= 0;

                bot0 <= 0;
                bot1 <= 0;


                top0_valid <= 1'b0;
                top1_valid <= 1'b0;

                mid0_valid <= 1'b0;
                mid1_valid <= 1'b0;

                bot0_valid <= 1'b0;
                bot1_valid <= 1'b0;


                window_valid_o <= 1'b0;

            end


            /*
             * 有效显示区域。
             */

            else if (de_i) begin


                /*
                 * 输出当前 3×3 Window。
                 *
                 * line2[x_count] = 前两行
                 * line1[x_count] = 前一行
                 * data_i         = 当前行
                 */

                window_o <= {

                    top0,
                    top1,
                    line2[x_count],

                    mid0,
                    mid1,
                    line1[x_count],

                    bot0,
                    bot1,
                    data_i

                };


                /*
                 * 只有 9 个位置全部有效，
                 * Window 才有效。
                 */

                window_valid_o <=

                       (line_count >= 2)
                    && (x_count >= 2)

                    && top0_valid
                    && top1_valid
                    && line2_valid[x_count]

                    && mid0_valid
                    && mid1_valid
                    && line1_valid[x_count]

                    && bot0_valid
                    && bot1_valid
                    && valid_i;


                /*
                 * Line Buffer 更新。
                 *
                 * old line1 → line2
                 * current   → line1
                 */

                line2[x_count] <=
                    line1[x_count];

                line1[x_count] <=
                    data_i;


                line2_valid[x_count] <=
                    line1_valid[x_count];

                line1_valid[x_count] <=
                    valid_i;


                /*
                 * 横向 shift register。
                 */

                top0 <= top1;
                top1 <= line2[x_count];

                mid0 <= mid1;
                mid1 <= line1[x_count];

                bot0 <= bot1;
                bot1 <= data_i;


                top0_valid <= top1_valid;
                top1_valid <= line2_valid[x_count];

                mid0_valid <= mid1_valid;
                mid1_valid <= line1_valid[x_count];

                bot0_valid <= bot1_valid;
                bot1_valid <= valid_i;


                x_count <= x_count + 1;

            end


            /*
             * Blank 区域。
             *
             * 每行开始前把横向 shift register 清空。
             */

            else begin

                x_count <= 0;

                top0 <= 0;
                top1 <= 0;

                mid0 <= 0;
                mid1 <= 0;

                bot0 <= 0;
                bot1 <= 0;


                top0_valid <= 1'b0;
                top1_valid <= 1'b0;

                mid0_valid <= 1'b0;
                mid1_valid <= 1'b0;

                bot0_valid <= 1'b0;
                bot1_valid <= 1'b0;


                window_valid_o <= 1'b0;


                /*
                 * DE下降沿：
                 * 一行结束。
                 */

                if (de_d && !de_i)

                    line_count <= line_count + 1;

            end

        end

    end


endmodule