`timescale 1ns/1ps
/* 2026-09-21 V0.4 / 13：替代顶层按键计数；加入同步与按下/释放双向消抖。
   低有效，稳定按下一次只产生一个时钟脉冲；长按不连发。 */
module key_debounce #(parameter DEBOUNCE_CYCLES=1920000)(
    input wire clk, rst_n, key_i,
    output reg pressed_o
);
    reg meta, synced, stable;
    reg [31:0] count;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin meta<=1; synced<=1; stable<=1; count<=0; pressed_o<=0; end
        else begin
            meta<=key_i; synced<=meta; pressed_o<=0;
            if (synced==stable) count<=0;
            else if (count==DEBOUNCE_CYCLES-1) begin
                stable<=synced; count<=0; pressed_o<=!synced;
            end else count<=count+1'b1;
        end
    end
endmodule
