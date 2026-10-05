`timescale 1ns/1ps
// Integration boundary: CPU-result clock -> existing processed pixel stream.
// pixel_overlay_enable must already be in pixel_clk domain, not raw UART/CPU data.
module cnn_overlay_bridge #(
    parameter IMAGE_WIDTH=1280, IMAGE_HEIGHT=720, MAX_AGE_FRAMES=30
)(
    input wire result_clk, result_rst_n, result_send,
    output wire result_ready,
    input wire result_valid,
    input wire [1:0] result_class,
    input wire [11:0] roi_x0,roi_y0,roi_x1,roi_y1,
    input wire [31:0] source_frame,
    input wire pixel_clk,pixel_rst_n,pixel_overlay_enable,
    input wire [23:0] rgb_i,
    input wire hs_i,vs_i,de_i,
    output wire [23:0] rgb_o,
    output wire hs_o,vs_o,de_o,
    output wire overlay_enabled,
    output wire [31:0] displayed_source_frame
);
    wire frame_boundary,commit;
    wire [82:0] message;
    wire [31:0] frame;
    wire valid;
    wire [1:0] cls;
    wire [11:0] x0,y0,x1,y1;
    assign {frame,valid,cls,x0,y0,x1,y1}=message;
    cnn_result_mailbox #(.WIDTH(83)) mailbox(
        .src_clk(result_clk),.src_rst_n(result_rst_n),.src_valid(result_send),
        .src_data({source_frame,result_valid,result_class,roi_x0,roi_y0,roi_x1,roi_y1}),
        .src_ready(result_ready),.dst_clk(pixel_clk),.dst_rst_n(pixel_rst_n),
        .frame_boundary(frame_boundary),.dst_data(message),.dst_commit(commit));
    cnn_video_overlay #(.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT),.MAX_AGE_FRAMES(MAX_AGE_FRAMES)) compositor(
        .clk(pixel_clk),.rst_n(pixel_rst_n),.rgb_i(rgb_i),.hs_i(hs_i),.vs_i(vs_i),.de_i(de_i),
        .overlay_enable_i(pixel_overlay_enable),.result_commit_i(commit),.result_valid_i(valid),
        .result_class_i(cls),.x0_i(x0),.y0_i(y0),.x1_i(x1),.y1_i(y1),.source_frame_i(frame),
        .rgb_o(rgb_o),.hs_o(hs_o),.vs_o(vs_o),.de_o(de_o),.frame_boundary_o(frame_boundary),
        .overlay_enabled_o(overlay_enabled),.displayed_source_frame_o(displayed_source_frame));
endmodule
