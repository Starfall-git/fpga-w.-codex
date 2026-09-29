`timescale 1ns/1ps
/* V0.14 / 66: sample one processed RGB888 row of the DDR-frozen frame.
   Toggle mailbox: row_i stable until ack; BRAM immutable from ack until
   the next request. Synchronous read port avoids asynchronous RAM inference.
   Always wait for next VS blanking before capture, never accept a partial row. */
module snapshot_line #(parameter WIDTH=1280)(
 input wire pixel_clk, pixel_rst_n, vs_i, de_i,
 input wire [23:0] rgb_i,
 input wire request_i,
 input wire [15:0] row_i,
 output reg ack_o,
 input wire sys_clk,
 input wire [10:0] read_addr_i,
 output reg [23:0] read_data_o
);
 reg [23:0] memory [0:WIDTH-1];
 reg req_meta,req_sync,active,armed;
 reg [15:0] x,y,target;
 wire capture = active && armed && de_i && y==target;
 always @(posedge pixel_clk) if(capture) memory[x]<=rgb_i;
 always @(posedge sys_clk) read_data_o<=memory[read_addr_i];
 always @(posedge pixel_clk or negedge pixel_rst_n) begin
  if(!pixel_rst_n) begin
   req_meta<=0; req_sync<=0; ack_o<=0; active<=0; armed<=0;
   x<=0; y<=0; target<=0;
  end else begin
   req_meta<=request_i; req_sync<=req_meta;
   if(!active && req_sync!=ack_o) begin active<=1;armed<=0;target<=row_i;end
   if(!vs_i) begin
    x<=0;y<=0;
    if(active) armed<=1;
   end else if(de_i) begin
    if(x==WIDTH-1) begin
     x<=0;y<=y+1'b1;
     if(capture) begin ack_o<=req_sync;active<=0;armed<=0;end
    end else x<=x+1'b1;
   end
  end
 end
endmodule
