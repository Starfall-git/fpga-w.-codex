`timescale 1ns/1ps
/* V0.4: independent UART bit driver/monitor, protocol errors, CDC and key tests. */
module uart_control_tb;
    reg clk=0, pixel_clk=0, rst=0, rx=1, blank=0;
    reg [1:0] keys=3;
    wire tx;
    wire [11:0] threshold;
    wire [23:0] edge_rgb;
    /* Fixed window |Gx|=128: serial threshold change must affect actual Sobel output. */
    /* V0.9 / 46: standalone Sobel in this checkout has no IMAGE_WIDTH parameter. */
    video_sobel sobel(.clk(pixel_clk),.rst_n(rst),.THRESHOLD(threshold),.BINARY_OUTPUT(1'b1),
        .pixels_i({8'd0,8'd0,8'd32,8'd0,8'd0,8'd32,8'd0,8'd0,8'd32}),
        .hs_i(1'b1),.vs_i(1'b1),.de_i(1'b1),.window_valid_i(1'b1),
        .rgb_o(edge_rgb),.hs_o(),.vs_o(),.de_o());
    always #5 clk=~clk;
    always #7 pixel_clk=~pixel_clk;
    /* V0.5: retain V0.4 regression with transform capability explicitly disabled. */
    uart_image_control #(.CLOCK_HZ(1000000),.BAUD(100000),.DEBOUNCE_CYCLES(4),.TRANSFORM_ENABLE(0)) dut
        (.clk(clk),.rst_n(rst),.uart_rx_i(rx),.uart_tx_o(tx),.key_data(keys),
         .pixel_clk(pixel_clk),.pixel_rst_n(rst),.frame_blank_i(blank),.threshold_pixel_o(threshold),
         .enable_sobel_o(),.binary_output_o(),.enable_median_o(), /* V0.9 median tested in uart_geometry_tb. */
         .geometry_o(),.geometry_toggle_o(),.geometry_ack_i(1'b0),.transform_faults_i(2'b00));
    localparam BIT=100;
    reg [7:0] received[0:1023];
    reg [7:0] byte_value;
    integer count=0, i;
    // Independent receiver samples the physical TX line at bit centers.
    initial forever begin
        @(negedge tx);
        #(BIT/2);
        if(tx!==0) $fatal(1,"TX start bit");
        for(i=0;i<8;i=i+1) begin #BIT; byte_value[i]=tx; end
        #BIT;
        if(tx!==1) $fatal(1,"TX stop bit");
        received[count]=byte_value; count=count+1;
    end
    function [7:0] crc8;
        input [7:0] a,b;
        integer j;
        reg [7:0] c;
        begin
            c=a^b;
            for(j=0;j<8;j=j+1) begin
                if(c[7]) c=(c<<1)^8'h07; else c=c<<1;
            end
            crc8=c;
        end
    endfunction
    task send_byte(input [7:0] value);
        integer b;
        begin
            rx=0; #BIT;
            for(b=0;b<8;b=b+1) begin rx=value[b]; #BIT; end
            rx=1; #BIT;
        end
    endtask
    task send_frame(input [7:0] seq, cmd, input [63:0] body, input bad_crc);
        integer b;
        reg [7:0] c;
        begin
            send_byte(8'ha5); send_byte(8'h5a); send_byte(seq); send_byte(cmd);
            c=crc8(crc8(0,seq),cmd);
            for(b=0;b<8;b=b+1) begin send_byte(body[b*8+:8]); c=crc8(c,body[b*8+:8]); end
            send_byte(c ^ {7'd0,bad_crc});
        end
    endtask
    integer consumed=0;
    task expect_reply(input [7:0] seq, cmd, status, input [11:0] value);
        integer b;
        reg [7:0] c;
        begin
            wait(count>=consumed+13);
            if(received[consumed]!==8'ha5 || received[consumed+1]!==8'h5a ||
               received[consumed+2]!==seq || received[consumed+3]!==(cmd|8'h80) ||
               received[consumed+4]!==status ||
               {received[consumed+6],received[consumed+5]}!=={4'd0,value} ||
               received[consumed+7]!==1 || received[consumed+8]!==8'hd1 ||
               received[consumed+9]!==0 || received[consumed+10]!==0 || received[consumed+11]!==0)
                $fatal(1,"Response mismatch seq=%d status=%d threshold=%d",seq,received[consumed+4],{received[consumed+6],received[consumed+5]});
            c=0;
            for(b=2;b<12;b=b+1) c=crc8(c,received[consumed+b]);
            if(c!==received[consumed+12]) $fatal(1,"Response CRC");
            consumed=consumed+13;
            #(BIT*2);
        end
    endtask
    task key_press(input [1:0] value);
        begin keys=value; #300; keys=3; #300; end
    endtask
    initial begin
        #43; rst=1; #200;
        send_frame(1,1,0,0); expect_reply(1,1,0,128);
        repeat(160) @(negedge pixel_clk);
        @(posedge pixel_clk); #1;
        if(edge_rgb!==24'hffffff) $fatal(1,"Initial Sobel threshold equality");
        send_frame(2,16,256,0);
        #3000;
        if(threshold!==128 || count!=consumed) $fatal(1,"Applied/ACK before blank");
        key_press(2); // Serial transaction owns threshold while waiting.
        blank=1;
        expect_reply(2,16,0,256);
        if(threshold!==256) $fatal(1,"CDC apply");
        repeat(160) @(negedge pixel_clk);
        @(posedge pixel_clk); #1;
        if(edge_rgb!==0) $fatal(1,"Runtime threshold not reaching Sobel");
        send_frame(3,16,4096,0); expect_reply(3,16,2,256);
        send_frame(4,16,100,1); expect_reply(4,16,1,256);
        send_frame(5,32,1,0); expect_reply(5,32,3,256);
        send_frame(6,33,0,0); expect_reply(6,33,3,256);
        send_frame(7,34,0,0); expect_reply(7,34,3,256);
        send_frame(8,1,1,0); expect_reply(8,1,2,256);
        // Truncated packet must expire, then a fresh header works.
        send_byte(8'ha5); send_byte(8'h5a); send_byte(77); #110000;
        send_frame(9,1,0,0); expect_reply(9,1,0,256);
        // Short start glitch and bad stop bit must not change threshold.
        rx=0; #10; rx=1; #1000;
        rx=0; #(BIT*10); rx=1; #(BIT*3);
        send_frame(10,1,0,0); expect_reply(10,1,0,256);
        keys=2; #10; keys=3; #200;
        if(threshold!==256) $fatal(1,"Key bounce");
        keys=2; #2000;
        if(threshold!==257) $fatal(1,"Key hold repeated/missed");
        keys=3; #300;
        key_press(1);
        if(threshold!==256) $fatal(1,"Key down");
        key_press(0);
        if(threshold!==256) $fatal(1,"Both keys");
        send_frame(11,16,4095,0); expect_reply(11,16,0,4095);
        key_press(2);
        if(threshold!==4095) $fatal(1,"Upper saturation");
        send_frame(12,16,0,0); expect_reply(12,16,0,0);
        key_press(1);
        if(threshold!==0) $fatal(1,"Lower saturation");
        send_frame(13,16,0,0); expect_reply(13,16,0,0);
        blank=0;
        send_frame(14,16,123,0); #1000;
        rst=0; #50; rst=1; #500;
        if(threshold!==128) $fatal(1,"Reset");
        send_frame(15,1,0,0); expect_reply(15,1,0,128);
        $display("PASS UART: physical 8N1, CRC, errors, frame-boundary CDC, keys, limits, reset");
        $finish;
    end
    initial begin #2000000; $fatal(1,"Test timeout"); end
endmodule
