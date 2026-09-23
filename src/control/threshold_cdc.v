`timescale 1ns/1ps
/* 2026-09-21 V0.4 / 15：阈值跨时钟邮箱。
   src 数据从请求翻转到 ack 返回期间保持不变；目标域先同步请求，
   仅在 HDMI 输出场消隐期间采样稳定的多位邮箱并确认，避免一帧中途换阈值。
   两域复位必须共同来自系统锁定条件；src_request_i 仅在 busy_o=0 时提交。
   applied_o 是已确认的值，不能用 desired 值冒充硬件已生效状态。 */
/* V0.6 / 25: parameterize mailbox width/reset to reuse for runtime ISP flags. */
module threshold_cdc #(parameter WIDTH=12, parameter RESET_VALUE=128)(
    input wire src_clk, src_rst_n,
    input wire src_request_i,
    input wire [WIDTH-1:0] src_value_i,
    output wire busy_o,
    output reg [WIDTH-1:0] applied_o,
    input wire pixel_clk, pixel_rst_n, frame_blank_i,
    output reg [WIDTH-1:0] pixel_value_o
);
    reg [WIDTH-1:0] mailbox;
    reg request_toggle, acknowledge;
    reg ack_meta, ack_sync, ack_seen;
    reg req_meta, req_sync;
    /* 等 applied_o 完成更新后才释放 busy，防止源端重复发送旧快照。 */
    assign busy_o=(request_toggle!=ack_sync) || (ack_seen!=ack_sync);
    always @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n) begin
            mailbox<=RESET_VALUE; request_toggle<=0; ack_meta<=0; ack_sync<=0; ack_seen<=0; applied_o<=RESET_VALUE;
        end else begin
            ack_meta<=acknowledge; ack_sync<=ack_meta;
            if (ack_seen!=ack_sync) begin ack_seen<=ack_sync; applied_o<=mailbox; end
            if (src_request_i && !busy_o) begin mailbox<=src_value_i; request_toggle<=~request_toggle; end
        end
    end
    always @(posedge pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n) begin req_meta<=0; req_sync<=0; acknowledge<=0; pixel_value_o<=RESET_VALUE; end
        else begin
            req_meta<=request_toggle; req_sync<=req_meta;
            if ((req_sync!=acknowledge) && frame_blank_i) begin
                pixel_value_o<=mailbox;
                acknowledge<=req_sync;
            end
        end
    end
endmodule
