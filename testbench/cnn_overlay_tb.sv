`timescale 1ns/1ps
module cnn_overlay_tb;
    reg sclk=0,pclk=0; always #7 sclk=~sclk; always #5 pclk=~pclk;
    reg srst=0,prst=0,send=0,boundary=0;
    reg [82:0] data=0; wire ready,commit; wire [82:0] received;
    cnn_result_mailbox box(.src_clk(sclk),.src_rst_n(srst),.src_valid(send),.src_data(data),
        .src_ready(ready),.dst_clk(pclk),.dst_rst_n(prst),.frame_boundary(boundary),
        .dst_data(received),.dst_commit(commit));
    reg [23:0] rgb=0; reg hs=0,vs=0,de=0,enable=0,rv=0,rc=0;
    reg [1:0] cls=0; reg [11:0] x0=1,y0=1,x1=15,y1=11; reg [31:0] seq=0;
    wire [23:0] out; wire oh,ov,od,frame_start; wire [31:0] shown;
    reg bridge_send=0; wire bridge_ready;
    wire [23:0] bridge_rgb; wire bh,bv,bd; wire [31:0] bridge_frame;
    cnn_overlay_bridge #(.IMAGE_WIDTH(16),.IMAGE_HEIGHT(12),.MAX_AGE_FRAMES(30)) bridge(
        .result_clk(sclk),.result_rst_n(srst),.result_send(bridge_send),.result_ready(bridge_ready),
        .result_valid(1'b1),.result_class(2'd0),.roi_x0(12'd1),.roi_y0(12'd1),.roi_x1(12'd15),.roi_y1(12'd11),
        .source_frame(32'd42),.pixel_clk(pclk),.pixel_rst_n(prst),.pixel_overlay_enable(1'b1),
        .rgb_i(rgb),.hs_i(hs),.vs_i(vs),.de_i(de),.rgb_o(bridge_rgb),.hs_o(bh),.vs_o(bv),.de_o(bd),
        .displayed_source_frame(bridge_frame));
    cnn_video_overlay #(.IMAGE_WIDTH(16),.IMAGE_HEIGHT(12),.MAX_AGE_FRAMES(3)) overlay(
        .clk(pclk),.rst_n(prst),.rgb_i(rgb),.hs_i(hs),.vs_i(vs),.de_i(de),
        .overlay_enable_i(enable),.result_commit_i(rc),.result_valid_i(rv),
        .result_class_i(cls),.x0_i(x0),.y0_i(y0),.x1_i(x1),.y1_i(y1),.source_frame_i(seq),
        .rgb_o(out),.hs_o(oh),.vs_o(ov),.de_o(od),.frame_boundary_o(frame_start),.displayed_source_frame_o(shown));
    integer pixels=0;
    task put(input [82:0] value);
        begin wait(ready); @(negedge sclk); data=value; send=1;
          @(negedge sclk); send=0; end
    endtask
    task cross_boundary;
        begin @(negedge pclk); boundary=1; @(negedge pclk); boundary=0; end
    endtask
    task tick;
        begin @(posedge pclk); #1;
            if ({oh,ov,od} !== {hs,vs,de}) $fatal(1,"video sync changed");
            if ({bh,bv,bd} !== {hs,vs,de}) $fatal(1,"bridge sync changed");
        end
    endtask
    // Independently encoded 5x7 P glyph; the test never calls the RTL font function.
    localparam [34:0] P=35'b11110_10001_10001_11110_10000_10000_10000;
    localparam [34:0] R=35'b11110_10001_10001_11110_10100_10010_10001;
    localparam [34:0] S=35'b01110_10001_10000_01110_00001_10001_01110;
    task frame(input integer marked, input integer toggle_mid, input integer new_result);
        integer xx,yy; reg draw,bridge_draw; reg [23:0] expected,color; reg [34:0] font;
        begin
            font=cls==0 ? P : cls==1 ? R : S;
            color=cls==0 ? 24'h00ffff : cls==1 ? 24'hffff00 : 24'hff00ff;
            @(negedge pclk); vs=0; de=0; tick();
            @(negedge pclk); rc=new_result; rv=1; seq=seq+1; tick();
            @(negedge pclk); rc=0; tick();
            @(negedge pclk); vs=1; tick();
            for(yy=0;yy<12;yy=yy+1) begin
                for(xx=0;xx<16;xx=xx+1) begin
                    @(negedge pclk); de=1; hs=1; rgb=24'h100000+yy*16+xx;
                    if(toggle_mid && yy==3 && xx==6) enable=~enable;
                    // A rogue producer commit during active video must not alter the ROI.
                    if(yy==5 && xx==4) begin rc=1; x0=9; end
                    else begin rc=0; x0=1; end
                    draw=marked && xx>=1 && xx<15 && yy>=1 && yy<11 &&
                         (xx==1 || xx==14 || yy==1 || yy==10);
                    if(marked && xx>=4 && xx<9 && yy>=4 && yy<11)
                        draw=draw || font[(6-(yy-4))*5+(4-(xx-4))];
                    expected=draw ? color : rgb;
                    tick(); if(out!==expected) $fatal(1,"pixel x=%d y=%d got=%h expected=%h",xx,yy,out,expected);
                    bridge_draw=xx>=1 && xx<15 && yy>=1 && yy<11 && (xx==1 || xx==14 || yy==1 || yy==10);
                    if(xx>=4 && xx<9 && yy>=4 && yy<11)
                        bridge_draw=bridge_draw || P[(6-(yy-4))*5+(4-(xx-4))];
                    if(bridge_frame!==42 || bridge_rgb!==(bridge_draw ? 24'h00ffff : rgb))
                        $fatal(1,"integrated bridge payload/pixel mismatch");
                    pixels=pixels+1;
                end
                @(negedge pclk); de=0; hs=0; rgb=24'h123456; tick();
                if(out!==rgb) $fatal(1,"blanking RGB changed");
                @(negedge pclk); tick();
            end
            @(negedge pclk); de=0; rc=0; tick();
        end
    endtask
    initial begin
        #40; srst=1; prst=1;
        put(83'h123456789); repeat(8) @(posedge pclk);
        if(ready || received!==0 || commit) $fatal(1,"mailbox committed without boundary");
        // Busy changes must not tear/replace the accepted payload.
        @(negedge sclk); data=83'h7abcdef; send=1;
        repeat(3) @(negedge sclk); send=0;
        cross_boundary(); repeat(5) @(posedge sclk);
        if(received!==83'h123456789 || !ready) $fatal(1,"mailbox data/ack failure");
        srst=0; #23; srst=1; put(83'h33445566); repeat(7) @(posedge pclk);
        cross_boundary(); repeat(5) @(posedge sclk);
        if(received!==83'h33445566 || !ready) $fatal(1,"source reset recovery failed");
        prst=0; #23; prst=1; put(83'h778899); repeat(7) @(posedge pclk);
        cross_boundary(); repeat(5) @(posedge sclk);
        if(received!==83'h778899 || !ready) $fatal(1,"destination reset recovery failed");
        wait(bridge_ready); @(negedge sclk); bridge_send=1;
        @(negedge sclk); bridge_send=0; repeat(5) @(posedge pclk);
        // Establish inactive VS then test full frames; metadata changes only in blank.
        @(negedge pclk); vs=1; enable=1; tick();
        frame(1,1,1);  // disable in middle: entire current frame still annotated
        frame(0,1,0);  // enable in middle: entire current frame still bypassed
        frame(1,0,1);  // fresh metadata
        frame(1,0,0); frame(1,0,0); frame(0,0,0); // age 3 expires
        x1=17; frame(0,0,1); // out-of-range result hidden
        x1=15; cls=1; frame(1,0,1); cls=2; frame(1,0,1);
        if(pixels!=9*16*12) $fatal(1,"pixel count changed");
        $display("PASS CNN overlay: %0d pixels, async mailbox, backpressure, reset, frame commit, disable, expiry, invalid ROI",pixels);
        $finish;
    end
    initial begin #1000000; $fatal(1,"timeout"); end
endmodule
