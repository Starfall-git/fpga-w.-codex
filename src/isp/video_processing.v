`timescale 1ns/1ps
/*
2026-09-18 V0.3 新增：DDR 显示数据至 HDMI 之间的图像处理封装。
接口统一为 clk/rst_n + RGB888/HS/VS/DE；每拍一个像素，没有 ready/反压。
V0.9：ENABLE_MEDIAN 与 ENABLE_SOBEL 独立选择原图、Median、Sobel、Median+Sobel。
V0.19：所有路径扩至39拍；新增功能关闭时保持原Sobel像素结果，仅增加对齐延迟。
控制信号由串口在场消隐边界提交。
后续高斯滤波等模块可在本封装中串联，必须同时传递 RGB 和全部同步信号。
*/
module video_processing #(
    parameter IMAGE_WIDTH   = 1280,
    /* V0.11 / 52: AR0135 monochrome=0; RGB color camera=1. */
    parameter ENABLE_GRAY = 0,
    /* V0.11 / 53: reference center-luminance threshold with UART floor. */
    parameter SOBEL_ADAPTIVE = 1,
    /* V0.10 / 50: suppress initial Sobel halo caused by non-image border
       pixels or a DDR/display startup margin. Eight pixels out of 1280x720. */
    parameter SOBEL_BORDER_GUARD = 8,
	/* V0.6 / 25: old ENABLE_SOBEL/SOBEL_BINARY parameters replaced by ports.
		Optional grayscale diagnostic kept separate from black/white polarity. */
    parameter GRAYSCALE_OUTPUT = 0,
    parameter VS_ACTIVE     = 1'b0
)(
    input  wire			clk,
    input  wire			rst_n,
    /* V0.9 / 41: 新增独立中值滤波开关，复位默认关闭，由像素域邮箱驱动。 */
    input  wire			ENABLE_SOBEL, ENABLE_MEDIAN, BINARY_OUTPUT,
    /* V0.16 / 76-78: independently bypassable denoise; exclusive edge selection. */
    /* V0.19 / 89-91: tuning arrives through frame-boundary CDC. */
    input wire [15:0] ISP_TUNING,
    input wire ENABLE_GAUSSIAN, ENABLE_SCHARR, ENABLE_CANNY, PRESERVE_EDGES,
	/* V0.4 / 13、15：保留用户改为变量的阈值接口；输入须已同步到本clk域。 */
    input  wire [11:0]	SOBEL_THRESHOLD,

    input  wire [23:0]	rgb_i,
    input  wire			hs_i,
    input  wire			vs_i,
    input  wire			de_i,

    output wire [23:0]	rgb_o,
    output wire			hs_o,
    output wire			vs_o,
    output wire			de_o
);

    /* V0.11 / 52: 原 gray_sum=(R+2G+B)/4 及其寄存器移至独立模块。
       ENABLE_GRAY=1 使用参考工程 306/601/117 权重；=0 取 G 亮度。
       两种选择均为三拍，AR0135 RGB565 的 G 保留六位亮度，R/B 仅五位。 */
    wire [7:0] gray;
    wire gray_hs, gray_vs, gray_de;
    video_rgb2gray #(.ENABLE_GRAY(ENABLE_GRAY), .VS_ACTIVE(VS_ACTIVE)) u_gray (
        .clk(clk), .rst_n(rst_n), .rgb_i(rgb_i),
        .hs_i(hs_i), .vs_i(vs_i), .de_i(de_i),
        .gray_o(gray), .hs_o(gray_hs), .vs_o(gray_vs), .de_o(gray_de)
    );

    /* V0.9 / 42: 灰度到 Median 输出相差 5 拍，供纯 Sobel 路径使用。
       原始 RGB 到最终 Sobel 同步相差 13 拍；原图仍保留全部颜色。 */
    reg [7:0] gray_delay [0:4];
    /* V0.11 / 54: 灰度由一拍改为三拍，原图旁路同步扩为13拍。 */
    reg [23:0] original_delay [0:38];
    integer delay_index;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (delay_index=0; delay_index<5; delay_index=delay_index+1)
                gray_delay[delay_index] <= 0;
            for (delay_index=0; delay_index<39; delay_index=delay_index+1)
                original_delay[delay_index] <= 0;
        end else begin
            gray_delay[0] <= gray;
            for (delay_index=1; delay_index<5; delay_index=delay_index+1)
                gray_delay[delay_index] <= gray_delay[delay_index-1];
            original_delay[0] <= de_i ? rgb_i : 24'd0;
            for (delay_index=1; delay_index<39; delay_index=delay_index+1)
                original_delay[delay_index] <= original_delay[delay_index-1];
        end
    end



    /*==========================================================
     * V0.9 / 43: Median 与 Sobel 始终实例化，四种模式共享末级同步。
     *=========================================================*/

    generate


        /*======================================================
         * V0.9: 两个开关在共享的数据通路中选择四种结果。
         *
         * Median（可选） + Sobel（可选）
         *
         * Gray
         *   ↓
         * Window #1
         *   ↓
         * Median
         *   ↓
         * Window #2
         *   ↓
         * Sobel
         *=====================================================*/

        begin : g_median_sobel


            /*--------------------------------------------------
             * Window #1
             *
             * 为 Median 构造 3x3 原始灰度窗口
             *-------------------------------------------------*/

            wire [71:0] median_window_pixels;

            wire median_window_hs;
            wire median_window_vs;
            wire median_window_de;
            wire median_window_valid;


            video_window3x3 #(
                .IMAGE_WIDTH (IMAGE_WIDTH),
                .VS_ACTIVE   (VS_ACTIVE)
            )
            u_window_median (
                .clk            (clk),
                .rst_n          (rst_n),

                .gray_i         (gray),
                .pixel_valid_i  (gray_de),

                .hs_i           (gray_hs),
                .vs_i           (gray_vs),
                .de_i           (gray_de),

                .pixels_o       (median_window_pixels),

                .hs_o           (median_window_hs),
                .vs_o           (median_window_vs),
                .de_o           (median_window_de),

                .window_valid_o (median_window_valid)
            );



            /*--------------------------------------------------
             * Median-of-9
             *-------------------------------------------------*/

            wire [23:0] median_rgb;

            wire median_hs;
            wire median_vs;
            wire median_de;
            wire median_pixel_valid;


            video_median3x3 #(
                .VS_ACTIVE (VS_ACTIVE)
            )
            u_median (
                .clk            (clk),
                .rst_n          (rst_n),

                .pixels_i       (median_window_pixels),

                .hs_i           (median_window_hs),
                .vs_i           (median_window_vs),
                .de_i           (median_window_de),

                .window_valid_i (median_window_valid),

                .rgb_o          (median_rgb),

                .hs_o           (median_hs),
                .vs_o           (median_vs),
                .de_o           (median_de),
                .pixel_valid_o  (median_pixel_valid)
            );


            /*
             * Median 输出的是灰度 RGB：
             *
             * R = G = B = median
             *
             * 所以任取一个通道即可恢复灰度值。
             */

            wire [7:0] median_gray;

            assign median_gray = median_rgb[7:0];



            /*--------------------------------------------------
             * Window #2
             *
             * 为 Sobel 重新构造 3x3 窗口
             *
             * 注意：
             * ENABLE_MEDIAN=1 时窗口像素来自 Median；否则来自对齐后的原始灰度。
             *-------------------------------------------------*/

            /* V0.16: Gaussian adds three clocks on enabled and bypass paths.
               Canny always uses pre-smoothing. Existing Sobel arithmetic is untouched. */
            wire [7:0] first_filter,filtered;wire f1h,f1v,f1d,f1ok,fh,fv,fd,fok;
            video_gaussian #(.IMAGE_WIDTH(IMAGE_WIDTH),.VS_ACTIVE(VS_ACTIVE)) u_gaussian(
              .clk(clk),.rst_n(rst_n),.enable_i(ENABLE_GAUSSIAN || ENABLE_CANNY),.preserve_i(PRESERVE_EDGES),
              .gray_i(ENABLE_MEDIAN ? median_gray : gray_delay[4]),
              .valid_i(ENABLE_MEDIAN ? median_pixel_valid : median_de),
              .hs_i(median_hs),.vs_i(median_vs),.de_i(median_de),
              .gray_o(first_filter),.valid_o(f1ok),.hs_o(f1h),.vs_o(f1v),.de_o(f1d));
            /* V0.19 / 89: optional second binomial pass, equivalent interior kernel
               [1 4 6 4 1] outer product /256 apart from intermediate rounding.
               Disabled path still delays three clocks; original Sobel pixels unchanged. */
            video_gaussian #(.IMAGE_WIDTH(IMAGE_WIDTH),.VS_ACTIVE(VS_ACTIVE)) u_gaussian_second(
              .clk(clk),.rst_n(rst_n),.enable_i(ISP_TUNING[0] && (ENABLE_GAUSSIAN || ENABLE_CANNY)),.preserve_i(1'b0),
              .gray_i(first_filter),.valid_i(f1ok),.hs_i(f1h),.vs_i(f1v),.de_i(f1d),
              .gray_o(filtered),.valid_o(fok),.hs_o(fh),.vs_o(fv),.de_o(fd));
            wire [71:0] sobel_window_pixels;

            wire sobel_window_hs;
            wire sobel_window_vs;
            wire sobel_window_de;
            wire sobel_window_valid;


            video_window3x3 #(
                .IMAGE_WIDTH (IMAGE_WIDTH),
                .VS_ACTIVE   (VS_ACTIVE),
                /* V0.10 / 50: image border halo never enters edge detection. */
                .MIN_VALID_XY (SOBEL_BORDER_GUARD)
            )
            u_window_sobel (
                .clk            (clk),
                .rst_n          (rst_n),

                /* V0.9 / 43: Sobel 前选中值或同拍原始灰度。 */
                .gray_i         (filtered),
                /* V0.10 / 49: when Median is enabled, suppress all Sobel
                   windows touching its invalid first rows/columns. */
                .pixel_valid_i  (fok),

                .hs_i           (fh),
                .vs_i           (fv),
                .de_i           (fd),

                .pixels_o       (sobel_window_pixels),

                .hs_o           (sobel_window_hs),
                .vs_o           (sobel_window_vs),
                .de_o           (sobel_window_de),

                .window_valid_o (sobel_window_valid)
            );



            /*--------------------------------------------------
             * Sobel
             *-------------------------------------------------*/

            wire [23:0] sobel_rgb;
            wire sobel_hs;
            wire sobel_vs;
            wire sobel_de;

            /* The reference demo uses bin_en=0: 8-bit Gmax/2 strength. */
            sobeledge_8d_window #(
                .GRAYSCALE_OUTPUT (1),
                .ADAPTIVE_THRESHOLD (SOBEL_ADAPTIVE),
                .VS_ACTIVE     (VS_ACTIVE)
            )
            u_sobel (
                .clk            (clk),
                .rst_n          (rst_n),

				.BINARY_OUTPUT	(BINARY_OUTPUT),
                .THRESHOLD      (SOBEL_THRESHOLD),

                .pixels_i       (sobel_window_pixels),

                .hs_i           (sobel_window_hs),
                .vs_i           (sobel_window_vs),
                .de_i           (sobel_window_de),

                .window_valid_i (sobel_window_valid),

                .rgb_o          (sobel_rgb),

                .hs_o           (sobel_hs),
                .vs_o           (sobel_vs),
                .de_o           (sobel_de)
            );

            /* V0.16 / 77: parallel Scharr/streaming Canny. All output paths
               now share 39-clock timing; disabled new stages preserve old pixels. */
            wire [23:0] scharr_rgb,canny_rgb;wire ch,cv,cd;
            video_scharr_canny #(.IMAGE_WIDTH(IMAGE_WIDTH),.VS_ACTIVE(VS_ACTIVE)) u_advanced(
              .clk(clk),.rst_n(rst_n),.BINARY_OUTPUT(BINARY_OUTPUT),.THRESHOLD(SOBEL_THRESHOLD),.tuning_i(ISP_TUNING),
              .pixels_i(sobel_window_pixels),.window_valid_i(sobel_window_valid),
              .hs_i(sobel_window_hs),.vs_i(sobel_window_vs),.de_i(sobel_window_de),
              .scharr_o(scharr_rgb),.canny_o(canny_rgb),.hs_o(ch),.vs_o(cv),.de_o(cd));
            reg [23:0] edge_delay[0:19];
            reg [23:0] median_delay[0:30];
            reg [7:0] filter_delay[0:24];
            integer j;
            always @(posedge clk or negedge rst_n) begin
              if(!rst_n) begin
                for(j=0;j<20;j=j+1) edge_delay[j]<=0;
                for(j=0;j<31;j=j+1) median_delay[j]<=0;
                for(j=0;j<25;j=j+1) filter_delay[j]<=0;
              end else begin
                edge_delay[0]<=ENABLE_SCHARR ? scharr_rgb : sobel_rgb;
                for(j=1;j<20;j=j+1) edge_delay[j]<=edge_delay[j-1];
                median_delay[0]<=median_rgb;
                for(j=1;j<31;j=j+1) median_delay[j]<=median_delay[j-1];
                filter_delay[0]<=filtered;
                for(j=1;j<25;j=j+1) filter_delay[j]<=filter_delay[j-1];
              end
            end
            assign rgb_o=ENABLE_CANNY ? canny_rgb :
                (ENABLE_SCHARR || ENABLE_SOBEL) ? edge_delay[19] :
                ENABLE_GAUSSIAN ? {3{filter_delay[24]}} :
                ENABLE_MEDIAN ? median_delay[30] : original_delay[38];
            assign hs_o=ch;assign vs_o=cv;assign de_o=cd;



        end



    endgenerate


endmodule
