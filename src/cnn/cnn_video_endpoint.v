`timescale 1ns/1ps
// Derived EVSoC integration boundary: Sapphire APB, UART control and ISP video.
// All multi-bit result crossings are handled by cnn_result_mailbox.
module cnn_video_endpoint #(
    parameter IMAGE_WIDTH=1280, IMAGE_HEIGHT=720, MAX_AGE_FRAMES=30
)(
    input wire uart_clk, uart_rst_n,
    input wire [1:0] requested,
    output wire [1:0] applied,
    output wire available,
    input wire cpu_clk, cpu_rst_n, ai_online,
    output wire inference_enable,
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
    (* async_reg="true" *) reg infer_meta,infer_sync,overlay_meta,overlay_sync;
    (* async_reg="true" *) reg applied_infer_meta,applied_infer_sync;
    (* async_reg="true" *) reg applied_overlay_meta,applied_overlay_sync;
    (* async_reg="true" *) reg online_meta,online_sync;
    wire overlay_enabled;
    always @(posedge cpu_clk or negedge cpu_rst_n)
        if(!cpu_rst_n) begin infer_meta<=0;infer_sync<=0;end
        else begin infer_meta<=requested[0];infer_sync<=infer_meta;end
    assign inference_enable=infer_sync && ai_online && cpu_rst_n;
    always @(posedge pixel_clk or negedge pixel_rst_n)
        if(!pixel_rst_n) begin overlay_meta<=0;overlay_sync<=0;end
        else begin overlay_meta<=requested[1];overlay_sync<=overlay_meta;end
    always @(posedge uart_clk or negedge uart_rst_n)
        if(!uart_rst_n) begin
            applied_infer_meta<=0;applied_infer_sync<=0;
            applied_overlay_meta<=0;applied_overlay_sync<=0;online_meta<=0;online_sync<=0;
        end else begin
            applied_infer_meta<=inference_enable;applied_infer_sync<=applied_infer_meta;
            applied_overlay_meta<=overlay_enabled;applied_overlay_sync<=applied_overlay_meta;
            online_meta<=ai_online && cpu_rst_n;online_sync<=online_meta;
        end
    assign applied={applied_overlay_sync,applied_infer_sync};
    assign available=online_sync;
    wire send,ready,valid;
    wire [1:0] cls;
    wire [11:0] x0,y0,x1,y1;
    wire [31:0] frame;
    cnn_result_apb registers(.PCLK(cpu_clk),.PRESETn(cpu_rst_n),.PADDR(PADDR),
        .PSEL(PSEL),.PENABLE(PENABLE),.PWRITE(PWRITE),.PWDATA(PWDATA),.PRDATA(PRDATA),
        .PREADY(PREADY),.PSLVERROR(PSLVERROR),.control_status({ai_online,inference_enable}),.result_ready(ready),.result_send(send),
        .result_valid(valid),.result_class(cls),.roi_x0(x0),.roi_y0(y0),.roi_x1(x1),.roi_y1(y1),.source_frame(frame));
    cnn_overlay_bridge #(.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT),.MAX_AGE_FRAMES(MAX_AGE_FRAMES)) display(
        .result_clk(cpu_clk),.result_rst_n(cpu_rst_n),.result_send(send),.result_ready(ready),
        .result_valid(valid),.result_class(cls),.roi_x0(x0),.roi_y0(y0),.roi_x1(x1),.roi_y1(y1),.source_frame(frame),
        .pixel_clk(pixel_clk),.pixel_rst_n(pixel_rst_n),.pixel_overlay_enable(overlay_sync),
        .rgb_i(rgb_i),.hs_i(hs_i),.vs_i(vs_i),.de_i(de_i),.rgb_o(rgb_o),.hs_o(hs_o),.vs_o(vs_o),.de_o(de_o),
        .overlay_enabled(overlay_enabled),.displayed_source_frame(displayed_source_frame));
endmodule
