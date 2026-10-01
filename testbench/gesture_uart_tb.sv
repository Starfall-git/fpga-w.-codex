`timescale 1ns/1ps
// v1.1 / 16: Independent physical UART transactions, CRC, illegal args, defaults.
module gesture_uart_tb;
    reg clk=0,pclk=0,rst=0,rx=1;wire tx,en;
    always #5 clk=~clk;always #7 pclk=~pclk;
    uart_image_control #(.GESTURE_ENABLE(1),.TRANSFORM_ENABLE(0),.CLOCK_HZ(1000000),.BAUD(100000),.DEBOUNCE_CYCLES(4))dut(
        .clk(clk),.rst_n(rst),.uart_rx_i(rx),.uart_tx_o(tx),.key_data(2'b11),
        .pixel_clk(pclk),.pixel_rst_n(rst),.frame_blank_i(1'b1),
        .geometry_ack_i(1'b0),.transform_faults_i(2'b00),
        .gesture_enable_o(en),.gesture_flags_i(en?8'h0d:8'h18),
        .gesture_class_i(en?8'd4:8'hff),.gesture_margin_i(16'd512),.gesture_frame_i(16'h1234));
    localparam BIT=100;
    reg [7:0] received[0:511],byte_value;
    integer count=0,consumed=0,i;
    initial forever begin
        @(negedge tx);#(BIT/2);
        if(tx!==0)$fatal(1,"start bit");
        for(i=0;i<8;i=i+1)begin #BIT;byte_value[i]=tx;end
        #BIT;if(tx!==1)$fatal(1,"stop bit");
        received[count]=byte_value;count=count+1;
    end
    function [7:0] crc8(input[7:0]a,b);
        reg[7:0]c;integer j;
        begin c=a^b;for(j=0;j<8;j=j+1)c=c[7]?(c<<1)^8'h07:c<<1;crc8=c;end
    endfunction
    task send_byte(input[7:0]value);
        integer b;begin rx=0;#BIT;for(b=0;b<8;b=b+1)begin rx=value[b];#BIT;end rx=1;#BIT;end
    endtask
    task request(input[7:0]seq,cmd,input[63:0]payload,input bad);
        integer b;reg[7:0]crc;
        begin
            send_byte(8'ha5);send_byte(8'h5a);send_byte(seq);send_byte(cmd);
            crc=crc8(crc8(0,seq),cmd);
            for(b=0;b<8;b=b+1)begin send_byte(payload[b*8+:8]);crc=crc8(crc,payload[b*8+:8]);end
            send_byte(crc^{7'd0,bad});
        end
    endtask
    task response(input[7:0]seq,cmd,status);
        reg[7:0]crc;integer b;
        begin
            wait(count>=consumed+13);
            if(received[consumed]!=8'ha5 || received[consumed+1]!=8'h5a ||
               received[consumed+2]!=seq || received[consumed+3]!=(cmd|8'h80) ||
               received[consumed+4]!=status)$fatal(1,"response header");
            crc=0;for(b=2;b<12;b=b+1)crc=crc8(crc,received[consumed+b]);
            if(crc!=received[consumed+12])$fatal(1,"response CRC");
            consumed=consumed+13;#(BIT*3);
        end
    endtask
    initial begin
        #200;rst=1;repeat(50)@(negedge clk);
        request(1,8'h40,0,0);response(1,8'h40,0);
        if(en || received[5]!=8'h11 || received[7]!=255)$fatal(1,"reset state");
        request(2,8'h41,1,1);response(2,8'h41,1);if(en)$fatal(1,"CRC changed enable");
        request(3,8'h41,2,0);response(3,8'h41,2);if(en)$fatal(1,"bad args changed enable");
        request(4,8'h41,1,0);response(4,8'h41,0);if(!en)$fatal(1,"enable failed");
        request(5,8'h40,0,0);response(5,8'h40,0);
        if(received[consumed-13+5]!=8'h11 || received[consumed-13+6]!=13 ||
           received[consumed-13+7]!=4 || received[consumed-13+9]!=2 ||
           received[consumed-13+10]!=8'h34 || received[consumed-13+11]!=8'h12)$fatal(1,"status data mismatch");
        request(6,8'h40,1,0);response(6,8'h40,2);
        request(7,8'h41,0,0);response(7,8'h41,0);if(en)$fatal(1,"disable failed");
        request(8,8'h41,1,0);response(8,8'h41,0);
        request(9,8'h12,0,0);response(9,8'h12,0);if(en)$fatal(1,"defaults did not disable");
        $display("PASS GESTURE UART: status, enable, CRC, arguments, disable/defaults");$finish;
    end
    initial begin #5000000;$fatal(1,"UART timeout");end
endmodule
