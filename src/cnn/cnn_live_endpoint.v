`timescale 1ns/1ps
// APB address extension: original result ABI plus RAW8 snapshot window.
module cnn_live_endpoint #(
    parameter IMAGE_WIDTH=1280,IMAGE_HEIGHT=720,REQUIRE_FIRMWARE_READY=1
)(
    input wire uart_clk,uart_rst_n,
    input wire [1:0] requested,
    output wire [1:0] applied,
    output wire available,
    input wire cpu_clk,cpu_rst_n,ai_online,
    output wire inference_enable,
    input wire cam_clk,cam_rst_n,cam_frame_valid,cam_pixel_valid,
    input wire [7:0] cam_gray,
    input wire [15:0] PADDR,
    input wire PSEL,PENABLE,PWRITE,
    input wire [31:0] PWDATA,
    output wire [31:0] PRDATA,
    output wire PREADY,PSLVERROR,
    input wire pixel_clk,pixel_rst_n,
    input wire [23:0] rgb_i,
    input wire hs_i,vs_i,de_i,
    output wire [23:0] rgb_o,
    output wire hs_o,vs_o,de_o,
    output wire [31:0] displayed_source_frame
);
    wire capture_select=PADDR[15:5]==11'h002 || PADDR[15:12]==4'h1;
    wire [31:0] capture_data,result_data;
    wire capture_ready,capture_error,result_ready,result_error;
    assign PRDATA=capture_select ? capture_data : result_data;
    assign PREADY=capture_select ? capture_ready : result_ready;
    assign PSLVERROR=capture_select ? capture_error : result_error;
    cnn_gray_snapshot capture(.cam_clk(cam_clk),.cam_rst_n(cam_rst_n),
        .frame_valid(cam_frame_valid),.pixel_valid(cam_pixel_valid),.gray(cam_gray),
        .PCLK(cpu_clk),.PRESETn(cpu_rst_n),.PADDR(PADDR),.PSEL(PSEL && capture_select),
        .PENABLE(PENABLE),.PWRITE(PWRITE),.PWDATA(PWDATA),.PRDATA(capture_data),
        .PREADY(capture_ready),.PSLVERROR(capture_error));
    cnn_video_endpoint #(.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT),
        .REQUIRE_FIRMWARE_READY(REQUIRE_FIRMWARE_READY)) display(
        .uart_clk(uart_clk),.uart_rst_n(uart_rst_n),.requested(requested),.applied(applied),.available(available),
        .cpu_clk(cpu_clk),.cpu_rst_n(cpu_rst_n),.ai_online(ai_online),.inference_enable(inference_enable),
        .PADDR(PADDR),.PSEL(PSEL && !capture_select),.PENABLE(PENABLE),.PWRITE(PWRITE),.PWDATA(PWDATA),
        .PRDATA(result_data),.PREADY(result_ready),.PSLVERROR(result_error),
        .pixel_clk(pixel_clk),.pixel_rst_n(pixel_rst_n),.rgb_i(rgb_i),.hs_i(hs_i),.vs_i(vs_i),.de_i(de_i),
        .rgb_o(rgb_o),.hs_o(hs_o),.vs_o(vs_o),.de_o(de_o),.displayed_source_frame(displayed_source_frame));
endmodule
