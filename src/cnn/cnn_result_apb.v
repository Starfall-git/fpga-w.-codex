`timescale 1ns/1ps
// Sapphire APB slave result publisher. PCLK must equal mailbox result_clk.
// Shadow fields can change while a previous result is pending in the mailbox.
module cnn_result_apb(
    input wire PCLK, PRESETn,
    input wire [15:0] PADDR,
    input wire PSEL, PENABLE, PWRITE,
    input wire [31:0] PWDATA,
    output wire PREADY, PSLVERROR,
    output reg [31:0] PRDATA,
    input wire [1:0] control_status, // CPU-domain {online, inference_enable}
    input wire result_ready,
    output wire result_send,
    output wire result_valid,
    output wire [1:0] result_class,
    output wire [11:0] roi_x0, roi_y0, roi_x1, roi_y1,
    output reg firmware_ready,
    output wire [31:0] source_frame
);
    reg [31:0] frame, xy0, xy1, meta;
    reg [31:0] accepted_count;
    reg rejected;
    wire access = PSEL && PENABLE;
    wire commit_write = access && PWRITE && PADDR == 16'h0014;
    wire commit_ok = PWDATA == 32'd1 && result_ready;
    reg address_ok, write_ok;
    always @* begin
        PRDATA=0; address_ok=1; write_ok=0;
        case (PADDR)
            16'h0000: PRDATA=32'h47535431; // GST1: register ABI version 1
            16'h0004: PRDATA={30'b0,rejected,result_ready};
            16'h0008: begin PRDATA=frame; write_ok=1; end
            16'h000c: begin PRDATA=xy0; write_ok=1; end
            16'h0010: begin PRDATA=xy1; write_ok=1; end
            16'h0014: write_ok=1; // write 1: publish; reads return zero
            16'h0018: begin PRDATA=meta; write_ok=1; end
            16'h001c: PRDATA=accepted_count;
            16'h0024: PRDATA={30'd0,control_status};
            16'h0028: begin PRDATA={31'd0,firmware_ready}; write_ok=1; end
            16'h0020: write_ok=1; // write 1: clear rejected latch
            default: address_ok=0;
        endcase
    end
    // A busy publication fails immediately; it never waits for the video clock.
    assign PREADY=1'b1;
    assign PSLVERROR=access && (!address_ok || (PWRITE && !write_ok) ||
        (commit_write && !commit_ok) ||
        (access && PWRITE && PADDR==16'h0028 && PWDATA!=0 && PWDATA!=32'h47535452));
    assign result_send=PRESETn && commit_write && commit_ok;
    assign source_frame=frame;
    assign roi_x0=xy0[11:0]; assign roi_y0=xy0[27:16];
    assign roi_x1=xy1[11:0]; assign roi_y1=xy1[27:16];
    assign result_valid=meta[0]; assign result_class=meta[2:1];
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            frame<=0; xy0<=0; xy1<=0; meta<=0; accepted_count<=0; rejected<=0; firmware_ready<=0;
        end else if (access && PWRITE) begin
            if (commit_write && !commit_ok) rejected<=1;
            if (!PSLVERROR) case (PADDR)
                16'h0028: firmware_ready <= PWDATA==32'h47535452;
                16'h0008: frame<=PWDATA;
                16'h000c: xy0<=PWDATA & 32'h0fff0fff;
                16'h0010: xy1<=PWDATA & 32'h0fff0fff;
                16'h0018: meta<=PWDATA & 32'h7;
                16'h0014: accepted_count<=accepted_count+1'b1;
                16'h0020: if (PWDATA[0]) rejected<=0;
                default: begin end
            endcase
        end
    end
endmodule
