`timescale 1ns/1ps
/* V0.14 / 69: physical UART row payload, CRC, freeze ownership and controls. */
module snapshot_tb;
 reg clk=0,pixel_clk=0,rst=0,rx=1,vs=0,de=0;
 reg [23:0] rgb=0;
 wire tx,freeze_req,frozen;
 wire [1:0] wi,ri;
 reg wb=0,rb=0;
 always #5 clk=~clk;
 always #7 pixel_clk=~pixel_clk;
 ddr_frame_owner #(.SNAPSHOT_ENABLE(1)) owner(.clk(clk),.reset(!rst),
  .write_done(wb),.read_boundary(rb),.freeze_request(freeze_req),
  .write_index(wi),.read_index(ri),.frozen(frozen));
 integer tick=0;
 reg [1:0] pinned;
 reg was_frozen=0;
 always @(negedge clk) begin
  if(!rst) begin tick=0;wb=0;rb=0;was_frozen=0;end
  else begin
   tick=tick+1;wb=(tick%37==0);rb=(tick%53==0);
   if(wi==ri) $fatal(1,"writer overwrites reader");
   if(frozen && was_frozen && ri!=pinned) $fatal(1,"pinned frame moved");
   pinned=ri;was_frozen=frozen;
  end
 end
 integer x,y;
 initial forever begin
  repeat(4) @(negedge pixel_clk);
  vs=0;de=0;
  repeat(5) @(negedge pixel_clk);
  vs=1;
  for(y=0;y<3;y=y+1) begin
   for(x=0;x<8;x=x+1) begin
    de=1;rgb={8'(y),8'(x),8'(y^x)};@(negedge pixel_clk);
   end
   de=0;repeat(3) @(negedge pixel_clk);
  end
 end
 uart_image_control #(.SNAPSHOT_ENABLE(1),.IMAGE_WIDTH(8),.IMAGE_HEIGHT(3),
  .CLOCK_HZ(1000000),.BAUD(100000),.DEBOUNCE_CYCLES(4),.TRANSFORM_ENABLE(0)) dut(
  .clk(clk),.rst_n(rst),.pixel_clk(pixel_clk),.pixel_rst_n(rst),.frame_blank_i(!vs),
  .uart_rx_i(rx),.uart_tx_o(tx),.key_data(2'b11),.geometry_ack_i(1'b0),
  .transform_faults_i(2'b00),.freeze_request_o(freeze_req),.frozen_i(frozen),
  .snapshot_vs_i(vs),.snapshot_de_i(de),.snapshot_rgb_i(rgb));
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

 function [15:0] crc16;
 input [15:0] old;input [7:0] value;
 integer k;reg [15:0] c;
 begin c=old^{value,8'b0};for(k=0;k<8;k=k+1)c=c[15]?(c<<1)^16'h1021:c<<1;crc16=c;end
 endfunction
 integer used=0,j,row;
 reg [7:0] c8;
 reg [15:0] c16;
 task header(input [7:0] seq,cmd,code);
 begin
  wait(count>=used+13);
  if(received[used]!=8'ha5 || received[used+1]!=8'h5a || received[used+2]!=seq ||
     received[used+3]!=(cmd|8'h80) || received[used+4]!=code) $fatal(1,"bad header seq %0d status %0d",seq,received[used+4]);
  c8=0;for(j=2;j<12;j=j+1)c8=crc8(c8,received[used+j]);
  if(c8!=received[used+12])$fatal(1,"header CRC");
  used=used+13;#(BIT*2);
 end endtask
 initial begin
  #43;rst=1;#2000;
  send_frame(1,'h30,0,0);header(1,'h30,0);
  if(received[6]!=8 || received[8]!=3 || received[10]!=3 || received[11]!=1)$fatal(1,"info layout");
  send_frame(2,'h32,0,0);header(2,'h32,4);
  send_frame(3,'h31,1,0);header(3,'h31,0);
  if(!frozen)$fatal(1,"ACK before freeze boundary");
  send_frame(4,'h10,42,0);header(4,'h10,4);
  send_frame(5,'h32,3,0);header(5,'h32,2);
  for(row=0;row<3;row=row+1) begin
   send_frame(6+row,'h32,row,0);header(6+row,'h32,0);
   wait(count>=used+26);c16=16'hffff;
   for(j=0;j<24;j=j+1) begin
    if(received[used+j] !== (j%3==0 ? 8'(row) : j%3==1 ? 8'(j/3) : 8'(row^(j/3))))
     $fatal(1,"row %0d byte %0d = %0d",row,j,received[used+j]);
    c16=crc16(c16,received[used+j]);
   end
   if({received[used+25],received[used+24]}!==c16)$fatal(1,"row CRC16");
   used=used+26;#(BIT*3);
  end
  send_frame(10,'h31,0,0);header(10,'h31,0);
  if(frozen)$fatal(1,"resume ACK mismatch");
  send_frame(11,'h10,42,0);header(11,'h10,0);
  $display("PASS SNAPSHOT UART / RGB rows / CRC16 / pin ownership / control lock / resume");$finish;
 end
 initial begin #2000000;$fatal(1,"watchdog");end
endmodule
