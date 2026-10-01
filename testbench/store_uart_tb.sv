`timescale 1ns/1ps
module store_uart_tb;
 reg clk=0,pixel_clk=0,rst=0,rx=1;
 wire tx,toggle,ack;wire [31:0] cmd;wire [7:0] result;
 wire [11:0] saved,selected;wire [1:0] mode;wire [3:0] wi,ri;
 reg wb=0,rb=0;
 always #5 clk=~clk;always #7 pixel_clk=~pixel_clk;
 ddr_frame_store owner(.clk(clk),.reset(!rst),.write_done(wb),.read_boundary(rb),
 .command_toggle_i(toggle),.command_i(cmd),.command_ack_o(ack),.result_o(result),
 .write_index(wi),.read_index(ri),.saved_o(saved),.compare_o(selected),.mode_o(mode));
 integer tick=0;
 always @(negedge clk) begin
  if(!rst) begin tick=0;wb=0;rb=0;end
  else begin
   tick=tick+1;wb=(tick%37==0);rb=(tick%53==0);
   if(wi==ri || saved[wi]) $fatal(1,"writer overwrites protected frame");
  end
 end
 uart_image_control #(.SNAPSHOT_ENABLE(1),.CLOCK_HZ(1000000),.BAUD(100000),.DEBOUNCE_CYCLES(4),.TRANSFORM_ENABLE(0)) dut(
 .clk(clk),.rst_n(rst),.pixel_clk(pixel_clk),.pixel_rst_n(rst),.frame_blank_i(1'b1),
 .uart_rx_i(rx),.uart_tx_o(tx),.key_data(2'b11),.geometry_ack_i(1'b0),.transform_faults_i(2'b00),
 .store_command_o(cmd),.store_toggle_o(toggle),.store_ack_i(ack),.store_result_i(result),
 .store_saved_i(saved),.store_mode_i(mode),.store_display_i(ri));
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

 integer used=0,j,first;
 reg [11:0] retained;
 reg [3:0] paused;
 reg [7:0] c8;
 task header(input [7:0] seq,cmd,code);
 integer h;
 begin
  wait(count>=used+13);
  if(received[used]!=8'ha5 || received[used+1]!=8'h5a || received[used+2]!=seq ||
     received[used+3]!=(cmd|8'h80) || received[used+4]!=code) $fatal(1,"bad header seq %0d status %0d",seq,received[used+4]);
  c8=0;for(h=2;h<12;h=h+1)c8=crc8(c8,received[used+h]);
  if(c8!=received[used+12])$fatal(1,"header CRC");
  used=used+13;#(BIT*2);
 end endtask
 initial begin
  #200;rst=1;repeat(200) @(negedge clk);
  send_frame(1,8'h30,0,0);header(1,8'h30,0);
  if(received[5]!=2 || received[6]!=8) $fatal(1,"v2 capacity");
  used=count;
  for(j=0;j<8;j=j+1) begin
   send_frame(2+j,8'h31,1,0);header(2+j,8'h31,0);used=count;
   if(mode!=0) $fatal(1,"save stopped live display");
  end
  retained=saved;
  send_frame(11,8'h31,1,0);header(11,8'h31,7);used=count;
  repeat(500) @(negedge clk);if(saved!=retained) $fatal(1,"saved mask changed");
  send_frame(12,8'h31,2,0);header(12,8'h31,0);used=count;paused=ri;
  repeat(500) @(negedge clk);if(ri!=paused || mode!=1) $fatal(1,"pause failed");
  first=0;while(!saved[first]) first=first+1;
  send_frame(13,8'h31,(first<<8)|3,0);header(13,8'h31,0);used=count;
  if(mode!=2 || ri!=first) $fatal(1,"replay failed");
  send_frame(14,8'h31,(retained<<16)|4,0);header(14,8'h31,0);used=count;
  if(mode!=3 || selected!=retained) $fatal(1,"compare failed");
  send_frame(15,8'h32,0,0);header(15,8'h32,3);used=count;
  repeat(500) @(negedge clk);if(count!=used) $fatal(1,"unexpected pixel stream");
  send_frame(18,8'h12,0,0);header(18,8'h12,0);used=count;
  if(mode!=0 || saved!=retained) $fatal(1,"default must resume without deleting");
  send_frame(19,8'h31,32'h00000c03,0);header(19,8'h31,2);used=count;
  send_frame(16,8'h31,0,0);header(16,8'h31,0);used=count;
  send_frame(17,8'h31,5,0);header(17,8'h31,0);
  if(saved!=0 || mode!=0) $fatal(1,"clear failed");
  $display("PASS DDR STORE UART: 8 saved/live/pause/replay/compare/full/clear/no pixels");$finish;
 end
 initial begin #2000000;$fatal(1,"timeout");end
endmodule
