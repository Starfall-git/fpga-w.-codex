`timescale 1ns/1ps
module cnn_uart_endpoint_tb;
 reg clk=0,pixel_clk=0,cpu_clk=0,rst=0,cpu_rst=0,rx=1,blank=0,online=1;
 always #5 clk=~clk;
 always #7 pixel_clk=~pixel_clk;
 always #11 cpu_clk=~cpu_clk;
 wire tx,infer,available;
 wire [1:0] requested,applied;
 wire [23:0] rgb;
 wire hs,vs,de;
 reg [23:0] input_rgb=24'h123456;
 reg input_de=1;
 reg [15:0] paddr=0;
 reg psel=0,penable=0,pwrite=0;
 reg [31:0] pwdata=0;
 wire [31:0] prdata,displayed;
 wire pready,perr;
 uart_image_control #(.CLOCK_HZ(1000000),.BAUD(100000),.DEBOUNCE_CYCLES(4),.TRANSFORM_ENABLE(0),.CNN_ENABLE(1)) dut(
 .clk(clk),.rst_n(rst),.uart_rx_i(rx),.uart_tx_o(tx),.key_data(2'b11),
 .pixel_clk(pixel_clk),.pixel_rst_n(rst),.frame_blank_i(blank),.threshold_pixel_o(),
 .enable_sobel_o(),.binary_output_o(),.enable_median_o(),.tuning_pixel_o(),
 .enable_gaussian_o(),.enable_scharr_o(),.enable_canny_o(),.preserve_edges_o(),
 .geometry_o(),.geometry_toggle_o(),.geometry_ack_i(1'b0),.transform_faults_i(2'b00),
 .store_command_o(),.store_toggle_o(),.store_ack_i(1'b0),.store_result_i(8'd0),.store_saved_i(12'd0),
 .store_order_i(384'd0),.store_mode_i(2'd0),.store_display_i(4'd0),
 .camera_toggle_o(),.camera_command_o(),.camera_ready_i(1'b0),.camera_ack_i(1'b0),.camera_error_i(1'b0),.camera_data_i(16'd0),
 .cnn_requested_o(requested),.cnn_applied_i(applied),.cnn_available_i(available));
 cnn_video_endpoint #(.IMAGE_WIDTH(16),.IMAGE_HEIGHT(12),.REQUIRE_FIRMWARE_READY(1)) endpoint(
 .uart_clk(clk),.uart_rst_n(rst),.requested(requested),.applied(applied),.available(available),
 .cpu_clk(cpu_clk),.cpu_rst_n(cpu_rst),.ai_online(online),.inference_enable(infer),
 .PADDR(paddr),.PSEL(psel),.PENABLE(penable),.PWRITE(pwrite),.PWDATA(pwdata),
 .PRDATA(prdata),.PREADY(pready),.PSLVERROR(perr),
 .pixel_clk(pixel_clk),.pixel_rst_n(rst),.rgb_i(input_rgb),.hs_i(1'b1),.vs_i(!blank),.de_i(input_de),
 .rgb_o(rgb),.hs_o(hs),.vs_o(vs),.de_o(de),.displayed_source_frame(displayed));
 // Disabled/empty overlay must pass every pixel and sync in exactly one cycle,
 // even when CPU is held in reset or UART waits for a missing frame boundary.
 always @(posedge pixel_clk) if(rst) begin
   #1;
   if(rgb!==input_rgb || hs!==1 || vs!==!blank || de!==input_de) $fatal(1,"video disturbed by AI control");
 end
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
 task response(input [7:0] seq,cmd,status,input [1:0] actual,wanted,input bit avail);
 integer b; reg [7:0] c;
 begin
 wait(count>=consumed+13);
 if(received[consumed]!==8'ha5 || received[consumed+1]!==8'h5a ||
 received[consumed+2]!==seq || received[consumed+3]!==(cmd|8'h80) ||
 received[consumed+4]!==status || received[consumed+5]!=={6'd0,actual} ||
 received[consumed+6]!=={6'd0,wanted} || received[consumed+7]!=={7'd0,avail} ||
 received[consumed+8]!==1 || received[consumed+9]!==0 || received[consumed+10]!==0 || received[consumed+11]!==0)
 $fatal(1,"AI response seq %d: status %d applied %d requested %d",seq,received[consumed+4],received[consumed+5],received[consumed+6]);
 c=0;for(b=2;b<12;b=b+1)c=crc8(c,received[consumed+b]);
 if(c!==received[consumed+12])$fatal(1,"AI response CRC");
 consumed=consumed+13;#(BIT*2);
 end endtask
 task set_ready(input bit yes);
 begin
 @(negedge cpu_clk);paddr=16'h28;psel=1;penable=0;pwrite=1;pwdata=yes?32'h47535452:0;
 @(negedge cpu_clk);penable=1;#1;if(perr || !pready)$fatal(1,"ready APB write");
 @(negedge cpu_clk);psel=0;penable=0;pwrite=0;#300;
 end endtask
 task frame_edge;
 begin @(negedge pixel_clk);blank=1;input_de=0;repeat(8)@(negedge pixel_clk);end endtask
 initial begin
 #43;rst=1;cpu_rst=1;#300;
 send_frame(30,8'h50,0,0);response(30,8'h50,0,0,0,0);
 send_frame(31,8'h51,1,0);response(31,8'h51,3,0,0,0);
 set_ready(1);
 send_frame(1,8'h50,0,0);response(1,8'h50,0,0,0,1);
 send_frame(2,8'h51,1,0);response(2,8'h51,0,1,1,1);
 // CPU reads the actual inference gate through the same APB window.
 @(negedge cpu_clk);paddr=16'h24;psel=1;penable=0;
 @(negedge cpu_clk);penable=1;#1;
 if(prdata!==3 || !pready || perr)$fatal(1,"CPU control readback");
 @(negedge cpu_clk);psel=0;penable=0;
 // Both requested; inference already on, but overlay must wait for VS boundary.
 send_frame(3,8'h51,3,0);#1000;
 if(count!=consumed || applied!==1)$fatal(1,"overlay ACK before frame");
 frame_edge();response(3,8'h51,0,3,3,1);
 @(negedge pixel_clk);blank=0;input_de=1;
 send_frame(4,8'h51,2,0);response(4,8'h51,0,2,2,1);
 if(infer!==0)$fatal(1,"inference and overlay not independent");
 send_frame(5,8'h51,4,0);response(5,8'h51,2,2,2,1);
 // Invalid query and CRC retain state.
 send_frame(6,8'h50,1,0);response(6,8'h50,2,2,2,1);
 send_frame(22,8'h51,0,1);response(22,8'h51,1,2,2,1);
 send_frame(7,8'h51,0,0);#1000;
 if(count!=consumed || applied!==2)$fatal(1,"disable ACK before frame");
 frame_edge();response(7,8'h51,0,0,0,1);
 @(negedge pixel_clk);blank=0;input_de=1;
 online=0;#300;
 send_frame(8,8'h51,1,0);response(8,8'h51,3,0,0,0);
 // Overlay remains independently controllable when inference is offline.
 send_frame(20,8'h51,2,0);#1000;frame_edge();response(20,8'h51,0,2,2,0);
 @(negedge pixel_clk);blank=0;input_de=1;
 send_frame(21,8'h51,0,0);#1000;frame_edge();response(21,8'h51,0,0,0,0);
 @(negedge pixel_clk);blank=0;input_de=1;
 online=1;#300;
 // No VS: bounded timeout reports desired separately from actual; no fake ACK.
 send_frame(9,8'h51,2,0);response(9,8'h51,5,0,2,1);
 send_frame(10,8'h51,0,0);response(10,8'h51,0,0,0,1);
 // CPU reset must not reset or stop the video stream.
 cpu_rst=0;#300;
 send_frame(11,8'h50,0,0);response(11,8'h50,0,0,0,0);
 cpu_rst=1;#300;
 send_frame(32,8'h50,0,0);response(32,8'h50,0,0,0,0);
 set_ready(1);
 // DEFAULTS must wait for AI disable along with the original ISP defaults.
 send_frame(12,8'h51,3,0);#1000;frame_edge();response(12,8'h51,0,3,3,1);
 @(negedge pixel_clk);blank=0;input_de=1;
 send_frame(13,8'h12,0,0);#1000;
 if(count!=consumed || applied!==2)$fatal(1,"defaults ACK before overlay disabled");
 frame_edge();wait(count>=consumed+13);
 if(received[consumed+2]!==13 || received[consumed+3]!==8'h92 || received[consumed+4]!==0 ||
 requested!==0 || applied!==0)$fatal(1,"defaults incomplete");
 consumed=consumed+13;#(BIT*2);
 send_frame(14,8'h50,0,0);response(14,8'h50,0,0,0,1);
 set_ready(0);
 send_frame(33,8'h50,0,0);response(33,8'h50,0,0,0,0);
 $display("PASS CNN UART endpoint: independent enables, applied ACK, timeout, unavailable, video isolation");
 $finish;
 end
 initial begin #10000000;$fatal(1,"timeout");end
endmodule
