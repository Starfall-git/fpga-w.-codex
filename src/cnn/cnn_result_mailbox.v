`timescale 1ns/1ps
// One outstanding bundled-data transfer. Producer holds data until frame commit.
// Either endpoint reset clears only this link, never the camera/video pipeline.
module cnn_result_mailbox #(parameter WIDTH=83)(
    input wire src_clk, src_rst_n, src_valid,
    input wire [WIDTH-1:0] src_data,
    output wire src_ready,
    input wire dst_clk, dst_rst_n, frame_boundary,
    output reg [WIDTH-1:0] dst_data,
    output reg dst_commit
);
    wire link_rst_n = src_rst_n & dst_rst_n;
    (* async_reg = "true" *) reg [1:0] src_up, dst_up;
    (* async_reg = "true" *) reg ack_meta, ack_sync, req_meta, req_sync;
    reg req, ack;
    reg [WIDTH-1:0] held;
    always @(posedge src_clk or negedge link_rst_n)
        if (!link_rst_n) src_up <= 0; else src_up <= {src_up[0],1'b1};
    always @(posedge dst_clk or negedge link_rst_n)
        if (!link_rst_n) dst_up <= 0; else dst_up <= {dst_up[0],1'b1};
    assign src_ready = src_up[1] && (req == ack_sync);
    always @(posedge src_clk or negedge link_rst_n) begin
        if (!link_rst_n) begin req<=0; held<=0; ack_meta<=0; ack_sync<=0; end
        else if (!src_up[1]) begin req<=0; held<=0; ack_meta<=0; ack_sync<=0; end
        else begin
            ack_meta<=ack; ack_sync<=ack_meta;
            if (src_valid && src_ready) begin held<=src_data; req<=~req; end
        end
    end
    always @(posedge dst_clk or negedge link_rst_n) begin
        if (!link_rst_n) begin req_meta<=0; req_sync<=0; ack<=0; dst_data<=0; dst_commit<=0; end
        else if (!dst_up[1]) begin req_meta<=0; req_sync<=0; ack<=0; dst_data<=0; dst_commit<=0; end
        else begin
            req_meta<=req; req_sync<=req_meta; dst_commit<=0;
            if (frame_boundary && req_sync != ack) begin
                dst_data<=held; ack<=req_sync; dst_commit<=1;
            end
        end
    end
endmodule
