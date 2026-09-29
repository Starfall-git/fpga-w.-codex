`timescale 1ns/1ps
/*
2026-09-22 V0.5 / 19~21: RGB565 DDR row reader and nearest-neighbour transform.
Keep a complete source row (128-bit AXI) and two rendered display rows (16-bit).
Pixel domain owns displayed rows; request/ack toggles transfer stable mailboxes.
Frame switch waits for all old requests, never resets an outstanding AXI burst.
Geometry mailbox [97:82]=den, [81:66]=num, [65:50]=height, [49:34]=width,
[33:18]=y, [17:2]=x, [1]=horizontal flip, [0]=vertical flip.
Crop -> flip -> scale -> center on fixed WIDTH x HEIGHT canvas, black padding.
Source FIFO uses BIG ENDIAN: first RGB565 pixel in an AXI beat is bits127:112.
Both clocks must reset together. WIDTH must be divisible by 8; AXI is 128 bits.
*/
module axi_transform_reader #(
    parameter WIDTH=1280, HEIGHT=720, BUF_BITS=22, BASE_ADDR=0
)(
    input wire axi_clk, axi_reset,
    input wire [1:0] frame_index_i,
    output reg frame_switch_o,
    output reg [31:0] araddr_o,
    output reg [7:0] arlen_o,
    output reg arvalid_o,
    input wire arready_i,
    input wire [127:0] rdata_i,
    input wire [1:0] rresp_i,
    input wire rlast_i, rvalid_i,
    output wire rready_o,
    input wire pixel_clk, vs_i, request_i,
    output wire [15:0] pixel_o,
    input wire [97:0] geometry_i,
    input wire geometry_toggle_i,
    output reg geometry_ack_o,
    output wire [1:0] faults_o
);
    localparam ROW_BEATS=WIDTH/8;
    localparam [15:0] DEFAULT_W=WIDTH, DEFAULT_H=HEIGHT;
    localparam [97:0] DEFAULT_GEOMETRY={16'd1,16'd1,DEFAULT_H,DEFAULT_W,16'd0,16'd0,2'b00};
    /* V0.5: inferred synchronous simple dual-port RAM, no reset loops. */
    reg [127:0] source_ram [0:ROW_BEATS-1];
    reg [15:0] display_ram [0:2*WIDTH-1];
    reg [127:0] source_q;
    reg [15:0] display_q;
    reg display_good;
    assign pixel_o=display_good ? display_q : 16'd0;

    reg frame_req, frame_ack, line_req, line_ack;
    reg [11:0] requested_y;
    reg frame_meta, frame_sync, line_meta, line_sync;
    reg geometry_meta, geometry_sync;
    reg fa_meta, fa_sync, la_meta, la_sync;
    reg [11:0] px, display_y, fetch_y;
    reg [11:0] tag0, tag1;
    reg [1:0] bank_valid;
    reg line_pending, frame_pending, frame_needed, frame_ready;
    reg vs_last, line_good, underflow;
    reg [7:0] epoch, request_epoch;
    wire this_good=(px==0) ? (frame_ready && !frame_needed && bank_valid[display_y[0]] &&
                               ((display_y[0] ? tag1 : tag0)==display_y)) : line_good;
    always @(posedge pixel_clk) begin
        if(request_i) display_q<=display_ram[(display_y[0] ? WIDTH : 0)+px];
    end
    always @(posedge pixel_clk or posedge axi_reset) begin
        if(axi_reset) begin
            fa_meta<=0; fa_sync<=0; la_meta<=0; la_sync<=0;
            frame_req<=0; line_req<=0; requested_y<=0;
            px<=0; display_y<=0; fetch_y<=0; tag0<=0; tag1<=0; bank_valid<=0;
            line_pending<=0; frame_pending<=0; frame_needed<=0; frame_ready<=0;
            vs_last<=1; line_good<=0; display_good<=0; underflow<=0; epoch<=0; request_epoch<=0;
        end else begin
            fa_meta<=frame_ack; fa_sync<=fa_meta; la_meta<=line_ack; la_sync<=la_meta;
            vs_last<=vs_i;
            display_good<=request_i && this_good;
            if(line_pending && la_sync==line_req) begin
                line_pending<=0;
                if(request_epoch==epoch) begin
                    bank_valid[requested_y[0]]<=1;
                    if(requested_y[0]) tag1<=requested_y; else tag0<=requested_y;
                end
            end
            if(frame_pending && fa_sync==frame_req) begin frame_pending<=0; frame_ready<=1; end
            if(frame_needed && !frame_pending && !line_pending) begin
                frame_req<=~frame_req; frame_pending<=1; frame_needed<=0; frame_ready<=0;
            end
            if(frame_ready && !frame_needed && !line_pending && fetch_y<HEIGHT) begin
                if(fetch_y<display_y) fetch_y<=display_y;
                else if(fetch_y<=display_y+1'b1) begin
                    requested_y<=fetch_y; request_epoch<=epoch;
                    bank_valid[fetch_y[0]]<=0;
                    line_req<=~line_req; line_pending<=1; fetch_y<=fetch_y+1'b1;
                end
            end
            if(request_i) begin
                if(px==0) begin line_good<=this_good; if(!this_good) underflow<=1; end
                if(px==WIDTH-1) begin px<=0; display_y<=display_y+1'b1; end
                else px<=px+1'b1;
            end
            /* VS falling edge starts a frame transaction. Late old rows are discarded by epoch. */
            if(vs_last && !vs_i) begin
                px<=0; display_y<=0; fetch_y<=0; bank_valid<=0;
                frame_needed<=1; frame_ready<=0; line_good<=0; epoch<=epoch+1'b1;
            end
        end
    end

    localparam IDLE=0, FRAME_WAIT=1, FRAME_LATCH=2, PREP0=3, PREP1=4, PREP2=5,
               PREP3=6, PREP4=7, DIV_WAIT=8, ROW_Y=9, ROW_ADDR=10,
               BURST=11, AR=12, RD=13, RENDER_INIT=14, RENDER=15, DRAIN=16, PUBLISH=17;
    reg [4:0] state, div_return;
    reg div_start;
    reg [31:0] dividend, divisor;
    wire div_done;
    wire [31:0] quotient, remainder;
    unsigned_divider u_div(.clk(axi_clk),.rst_n(!axi_reset),.start_i(div_start),
        .dividend_i(dividend),.divisor_i(divisor),.busy_o(),.done_o(div_done),
        .quotient_o(quotient),.remainder_o(remainder));
    task divide;
        input [31:0] a,b;
        input [4:0] next_state;
        begin dividend<=a; divisor<=b; div_start<=1; div_return<=next_state; state<=DIV_WAIT; end
    endtask
    reg [97:0] geometry;
    wire [15:0] crop_x=geometry[17:2], crop_y=geometry[33:18];
    wire [15:0] crop_w=geometry[49:34], crop_h=geometry[65:50];
    wire [15:0] zoom_n=geometry[81:66], zoom_d=geometry[97:82];
    reg cfg_target, frame_target, line_target, render_bank;
    reg [31:0] frame_base;
    reg [15:0] scaled_w, pad_x, pad_y, visible_w, visible_h, skip_y;
    reg [15:0] x_initial, rem_initial, x_step, rem_step;
    reg [15:0] source_x_offset, x_remainder;
    reg [11:0] render_x, row_y;
    reg row_black, row_error, axi_error;
    reg [15:0] beat_offset, remaining_beats, burst_beats, beat_count;
    reg [31:0] next_addr;
    wire [8:0] page_beats=9'd256-{1'b0,next_addr[11:4]};
    wire [15:0] capped_beats=(remaining_beats>128) ? 16'd128 : remaining_beats;
    wire [15:0] selected_beats=(capped_beats>page_beats) ? {7'd0,page_beats} : capped_beats;
    wire [16:0] remainder_sum={1'b0,x_remainder}+{1'b0,rem_step};
    wire inside_x=(render_x>=pad_x && render_x<pad_x+visible_w);
    wire [15:0] mapped_x=geometry[1] ? crop_x+crop_w-1'b1-source_x_offset : crop_x+source_x_offset;
    reg render_en_d, render_good_d;
    reg [11:0] render_addr_d;
    reg [2:0] lane_d;
    assign rready_o=(state==RD);
    assign faults_o={axi_error,underflow};
    always @(posedge axi_clk) begin
        if(state==RD && rvalid_i && rready_o) source_ram[beat_offset]<=rdata_i;
        if(state==RENDER) source_q<=source_ram[inside_x && !row_black ? mapped_x[15:3] : 0];
        if(render_en_d) display_ram[render_addr_d]<=render_good_d ? source_q[127-lane_d*16 -: 16] : 16'd0;
    end
    always @(posedge axi_clk or posedge axi_reset) begin
        if(axi_reset) begin
            state<=IDLE; frame_switch_o<=0; frame_ack<=0; line_ack<=0; geometry_ack_o<=0;
            frame_meta<=0; frame_sync<=0; line_meta<=0; line_sync<=0; geometry_meta<=0; geometry_sync<=0;
            geometry<=DEFAULT_GEOMETRY; cfg_target<=0; frame_target<=0; line_target<=0;
            frame_base<=0; araddr_o<=0; arlen_o<=0; arvalid_o<=0;
            div_start<=0; dividend<=0; divisor<=1; div_return<=IDLE;
            scaled_w<=WIDTH; pad_x<=0; pad_y<=0; visible_w<=WIDTH; visible_h<=HEIGHT; skip_y<=0;
            x_initial<=0; rem_initial<=0; x_step<=1; rem_step<=0;
            source_x_offset<=0; x_remainder<=0; render_x<=0; row_y<=0; render_bank<=0;
            row_black<=0; row_error<=0; axi_error<=0;
            beat_offset<=0; remaining_beats<=0; burst_beats<=0; beat_count<=0; next_addr<=0;
            render_en_d<=0; render_good_d<=0; render_addr_d<=0; lane_d<=0;
        end else begin
            frame_meta<=frame_req; frame_sync<=frame_meta; line_meta<=line_req; line_sync<=line_meta;
            geometry_meta<=geometry_toggle_i; geometry_sync<=geometry_meta;
            div_start<=0; frame_switch_o<=0;
            render_en_d<=state==RENDER;
            render_good_d<=inside_x && !row_black && !row_error;
            render_addr_d<=(render_bank ? WIDTH : 0)+render_x;
            lane_d<=mapped_x[2:0];
            case(state)
                IDLE: begin
                    if(frame_sync!=frame_ack) begin
                        frame_switch_o<=1; frame_target<=frame_sync; state<=FRAME_WAIT;
                    end else if(line_sync!=line_ack) begin
                        line_target<=line_sync; row_y<=requested_y; render_bank<=requested_y[0];
                        row_error<=0; state<=ROW_Y;
                    end
                end
                FRAME_WAIT: state<=FRAME_LATCH;
                FRAME_LATCH: begin
                    frame_base<=BASE_ADDR+{frame_index_i,{BUF_BITS{1'b0}}};
                    if(geometry_sync!=geometry_ack_o) geometry<=geometry_i;
                    cfg_target<=geometry_sync; state<=PREP0;
                end
                PREP0: divide(crop_w*zoom_n,zoom_d,PREP1);
                PREP1: begin
                    scaled_w<=quotient[15:0];
                    pad_x<=quotient<WIDTH ? (WIDTH-quotient)/2 : 0;
                    visible_w<=quotient<WIDTH ? quotient : WIDTH;
                    divide(crop_h*zoom_n,zoom_d,PREP2);
                end
                PREP2: begin
                    pad_y<=quotient<HEIGHT ? (HEIGHT-quotient)/2 : 0;
                    visible_h<=quotient<HEIGHT ? quotient : HEIGHT;
                    skip_y<=quotient>HEIGHT ? (quotient-HEIGHT)/2 : 0;
                    divide((scaled_w>WIDTH ? (scaled_w-WIDTH)/2 : 0)*zoom_d,zoom_n,PREP3);
                end
                PREP3: begin x_initial<=quotient; rem_initial<=remainder; divide(zoom_d,zoom_n,PREP4); end
                PREP4: begin
                    x_step<=quotient; rem_step<=remainder;
                    geometry_ack_o<=cfg_target; frame_ack<=frame_target; state<=IDLE;
                end
                DIV_WAIT: if(div_done) state<=div_return;
                ROW_Y: begin
                    row_black<=!(row_y>=pad_y && row_y<pad_y+visible_h);
                    if(row_y>=pad_y && row_y<pad_y+visible_h)
                        divide((row_y-pad_y+skip_y)*zoom_d,zoom_n,ROW_ADDR);
                    else state<=RENDER_INIT;
                end
                ROW_ADDR: begin
                    next_addr<=frame_base+(geometry[0] ? crop_y+crop_h-1'b1-quotient : crop_y+quotient)*(WIDTH*2);
                    beat_offset<=0; remaining_beats<=ROW_BEATS; state<=BURST;
                end
                BURST: begin
                    araddr_o<=next_addr; arlen_o<=selected_beats-1'b1; burst_beats<=selected_beats;
                    beat_count<=0; arvalid_o<=1; state<=AR;
                end
                AR: if(arready_i) begin arvalid_o<=0; state<=RD; end
                RD: if(rvalid_i) begin
                    beat_offset<=beat_offset+1'b1; beat_count<=beat_count+1'b1;
                    if(rresp_i!=0 || (rlast_i!=(beat_count==burst_beats-1'b1))) begin row_error<=1; axi_error<=1; end
                    if(rlast_i) begin
                        remaining_beats<=remaining_beats-burst_beats; next_addr<=next_addr+burst_beats*16;
                        if(remaining_beats==burst_beats || beat_count!=burst_beats-1'b1) state<=RENDER_INIT;
                        else state<=BURST;
                    end
                end
                RENDER_INIT: begin render_x<=0; source_x_offset<=x_initial; x_remainder<=rem_initial; state<=RENDER; end
                RENDER: begin
                    if(inside_x) begin
                        source_x_offset<=source_x_offset+x_step+(remainder_sum>=zoom_n);
                        x_remainder<=remainder_sum>=zoom_n ? remainder_sum-zoom_n : remainder_sum;
                    end
                    if(render_x==WIDTH-1) state<=DRAIN; else render_x<=render_x+1'b1;
                end
                DRAIN: state<=PUBLISH;
                PUBLISH: begin line_ack<=line_target; state<=IDLE; end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
