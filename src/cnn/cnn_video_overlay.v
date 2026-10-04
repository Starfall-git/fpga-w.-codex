`timescale 1ns/1ps
// Pixel-domain compositor. One-cycle RGB/HS/VS/DE latency, no ready/backpressure.
// Results/enable are committed only during vertical blank. ROI max is exclusive.
module cnn_video_overlay #(
    parameter IMAGE_WIDTH=1280, IMAGE_HEIGHT=720, MAX_AGE_FRAMES=30,
    parameter VS_ACTIVE=1'b0
)(
    input wire clk, rst_n,
    input wire [23:0] rgb_i,
    input wire hs_i, vs_i, de_i,
    input wire overlay_enable_i,
    input wire result_commit_i, result_valid_i,
    input wire [1:0] result_class_i,
    input wire [11:0] x0_i, y0_i, x1_i, y1_i,
    input wire [31:0] source_frame_i,
    output reg [23:0] rgb_o,
    output reg hs_o, vs_o, de_o,
    output wire frame_boundary_o,
    output reg [31:0] displayed_source_frame_o
);
    reg prev_vs, prev_de, enabled, valid;
    reg [11:0] x,y,x0,y0,x1,y1;
    reg [1:0] class_id;
    reg [31:0] age;
    assign frame_boundary_o = (vs_i==VS_ACTIVE) && (prev_vs!=VS_ACTIVE);
    wire in_box = x>=x0 && x<x1 && y>=y0 && y<y1;
    wire border = in_box && (x==x0 || x==x1-1 || y==y0 || y==y1-1);
    // 5x7 P/R/S glyph at ROI+3; class order matches the frozen model.
    function [4:0] glyph_row;
        input [1:0] cls;
        input [2:0] row;
        begin
            glyph_row=0;
            case (cls)
                0: case(row)
                    0,3:glyph_row=5'b11110;
                    1,2:glyph_row=5'b10001;
                    4,5,6:glyph_row=5'b10000;
                   endcase
                1: case(row)
                    0,3:glyph_row=5'b11110;
                    1,2,6:glyph_row=5'b10001;
                    4:glyph_row=5'b10100;
                    5:glyph_row=5'b10010;
                   endcase
                2: case(row)
                    0,6:glyph_row=5'b01110;
                    1:glyph_row=5'b10001;
                    2:glyph_row=5'b10000;
                    3:glyph_row=5'b01110;
                    4:glyph_row=5'b00001;
                    5:glyph_row=5'b10001;
                   endcase
            endcase
        end
    endfunction
    wire label_area = in_box && x>=x0+3 && x<x0+8 && y>=y0+3 && y<y0+10;
    wire [2:0] label_row = y-y0-3;
    wire [2:0] label_col = x-x0-3;
    wire [4:0] row_bits = glyph_row(class_id,label_row);
    wire label_pixel = label_area && row_bits[4-label_col];
    wire [23:0] color = class_id==0 ? 24'h00ffff : class_id==1 ? 24'hffff00 : 24'hff00ff;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_vs<=VS_ACTIVE; prev_de<=0; enabled<=0; valid<=0;
            x<=0; y<=0; x0<=0; y0<=0; x1<=0; y1<=0; class_id<=0; age<=0;
            rgb_o<=0; hs_o<=0; vs_o<=VS_ACTIVE; de_o<=0; displayed_source_frame_o<=0;
        end else begin
            prev_vs<=vs_i; prev_de<=de_i;
            rgb_o<=de_i && enabled && valid && (border || label_pixel) ? color : rgb_i;
            hs_o<=hs_i; vs_o<=vs_i; de_o<=de_i;
            if (vs_i==VS_ACTIVE) begin x<=0; y<=0; end
            else if (de_i) x<=x+1'b1;
            else begin x<=0; if (prev_de) y<=y+1'b1; end
            if (frame_boundary_o) begin
                enabled<=overlay_enable_i;
                if (age<MAX_AGE_FRAMES) age<=age+1'b1;
                if (age>=MAX_AGE_FRAMES-1) valid<=0;
            end
            // Mailbox commit arrives one clock after boundary, still in blank.
            if (result_commit_i && vs_i==VS_ACTIVE) begin
                x0<=x0_i; y0<=y0_i; x1<=x1_i; y1<=y1_i; class_id<=result_class_i;
                valid<=result_valid_i && result_class_i<3 && x0_i<x1_i && y0_i<y1_i &&
                       x1_i<=IMAGE_WIDTH && y1_i<=IMAGE_HEIGHT;
                age<=0; displayed_source_frame_o<=source_frame_i;
            end
        end
    end
endmodule
