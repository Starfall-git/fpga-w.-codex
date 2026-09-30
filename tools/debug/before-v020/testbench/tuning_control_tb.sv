`timescale 1ns/1ps
/* V0.4: independent UART bit driver/monitor, protocol errors, CDC and key tests. */
module tuning_control_tb;
    reg clk=0, pixel_clk=0, rst=0, rx=1, blank=0;
    reg [1:0] keys=3;
    wire tx;
    wire [15:0] tuning_value;wire camera_toggle;wire [32:0] camera_command;
    reg camera_ack=0,camera_ready=1,camera_error=0;reg [15:0] camera_data=0;
    integer camera_commands=0;reg [32:0] last_camera_command;
    always @(posedge clk) begin
      if(rst && camera_ready && camera_ack!=camera_toggle) begin
        camera_ack<=camera_toggle;camera_data<=camera_command[32] ? 16'h1234 : camera_command[15:0];
        camera_commands<=camera_commands+1;last_camera_command<=camera_command;
      end
    end
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
    uart_image_control #(.CAMERA_ENABLE(1),.CLOCK_HZ(1000000),.BAUD(100000),.DEBOUNCE_CYCLES(4),.TRANSFORM_ENABLE(0)) dut
        (.clk(clk),.rst_n(rst),.uart_rx_i(rx),.uart_tx_o(tx),.key_data(keys),
         .pixel_clk(pixel_clk),.pixel_rst_n(rst),.frame_blank_i(blank),.threshold_pixel_o(threshold),
         .enable_sobel_o(),.binary_output_o(),.enable_median_o(), /* V0.9 median tested in uart_geometry_tb. */
         .tuning_pixel_o(tuning_value),.camera_toggle_o(camera_toggle),.camera_command_o(camera_command),
         .camera_ack_i(camera_ack),.camera_ready_i(camera_ready),.camera_error_i(camera_error),.camera_data_i(camera_data),
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
    reg [7:0] expected_flags=0;
    task check(input [7:0] seq,cmd,status,input [15:0] value);
        integer b;reg [7:0] c;
        begin
            wait(count>=consumed+13);
            if(received[consumed+2]!==seq || received[consumed+3]!==(cmd|8'h80) || received[consumed+4]!==status)
                $fatal(1,"reply seq/status %d %h",seq,received[consumed+4]);
            if(status==0 && cmd!=8'h12 && {received[consumed+6],received[consumed+5]}!==value)
                $fatal(1,"value seq%0d got%h expected%h",seq,{received[consumed+6],received[consumed+5]},value);
            c=0;for(b=2;b<12;b=b+1)c=crc8(c,received[consumed+b]);
            if(c!==received[consumed+12])$fatal(1,"CRC");
            consumed=consumed+13;#(BIT*2);
        end
    endtask
    task key_press(input [1:0] value);
        begin keys=value; #300; keys=3; #300; end
    endtask
    integer before_default;
    initial begin
        #43;rst=1;#200;
        send_frame(1,8'h15,0,0);check(1,8'h15,0,16'h3200);
        send_frame(2,8'h14,16'h190f,0);#1000;
        if(count!=consumed || tuning_value!=16'h3200)$fatal(1,"tuning applied before frame blank");
        blank=1;check(2,8'h14,0,16'h190f);
        if(tuning_value!=16'h190f)$fatal(1,"pixel tuning");
        send_frame(3,8'h14,16'h1800,0);check(3,8'h14,2,0);
        send_frame(4,8'h14,16'h4c00,0);check(4,8'h14,2,0);
        send_frame(5,8'h14,16'h3210,0);check(5,8'h14,2,0);
        send_frame(6,8'h40,{24'd0,16'd123,16'h3012,8'd1},0);check(6,8'h40,0,123);
        if(last_camera_command!={1'b0,16'h3012,16'd123})$fatal(1,"register address/data mapping");
        send_frame(7,8'h40,{24'd0,16'd0,16'h3164,8'd0},0);check(7,8'h40,0,16'h1234);
        if(last_camera_command!={1'b1,16'h3164,16'd0})$fatal(1,"read mapping");
        send_frame(8,8'h40,{24'd0,16'd673,16'h3012,8'd1},0);check(8,8'h40,2,0);
        send_frame(9,8'h40,{24'd0,16'h4480,16'h30B0,8'd1},0);check(9,8'h40,2,0);
        send_frame(10,8'h40,{24'd0,16'd0,16'h301A,8'd1},0);check(10,8'h40,2,0);
        send_frame(11,8'h40,{24'd0,16'd0,16'h3164,8'd1},0);check(11,8'h40,2,0);
        camera_error=1;
        send_frame(12,8'h40,{24'd0,16'd123,16'h3012,8'd1},0);check(12,8'h40,6,0);camera_error=0;
        camera_ready=0;
        send_frame(13,8'h40,{24'd0,16'd123,16'h3012,8'd1},0);check(13,8'h40,5,0);camera_ready=1;
        before_default=camera_commands;
        send_frame(14,8'h12,0,0);check(14,8'h12,0,0);
        if(camera_commands-before_default!=13 || last_camera_command!={1'b0,16'h3100,16'd19} || tuning_value!=16'h3200)
            $fatal(1,"defaults did not restore all sensor/tuning controls");
        camera_error=1;send_frame(15,8'h12,0,0);check(15,8'h12,6,0);
        $display("PASS TUNING: physical UART, frame CDC, sensor whitelist, read/write, NACK, unavailable, defaults");$finish;
    end
    initial begin #2000000;$fatal(1,"timeout");end
endmodule
