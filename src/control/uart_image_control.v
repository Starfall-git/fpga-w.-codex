`timescale 1ns/1ps
/*
2026-09-21 V0.4 / 13~16：按键和 UART 阈值仲裁、固定帧协议、CRC8、硬件回读。
帧：A5 5A SEQ CMD DATA[0..7] CRC8，共13字节；CRC覆盖SEQ..DATA7，poly=07/init=00。
CMD 01=查询，10=设置阈值(uint16 LE，其余6字节0)；其余返回未实现。
应答CMD=原CMD|80；DATA={status,阈值低,阈值高,版本1,能力位,0,0,0}。
status 0成功/1CRC错误/2参数错误/3未实现；能力bit0表示动态阈值。
上位机一次只发送一个请求并等待应答。设置成功应答在像素域确认应用后发送。
串口设置等待期间忽略按键新事件，避免刚设置的值被覆盖；其余时间保留按键加减。
*/
module uart_image_control #(
    parameter CLOCK_HZ=96000000,
    parameter BAUD=115200,
    parameter DEBOUNCE_CYCLES=1920000
)(
    input wire clk, rst_n,
    input wire uart_rx_i,
    output wire uart_tx_o,
    input wire [1:0] key_data,
    input wire pixel_clk, pixel_rst_n, frame_blank_i,
    output wire [11:0] threshold_pixel_o
);
    function [7:0] crc_next;
        input [7:0] crc, value;
        integer k;
        reg [7:0] c;
        begin
            c=crc^value;
            for(k=0;k<8;k=k+1) c=c[7] ? (c<<1)^8'h07 : c<<1;
            crc_next=c;
        end
    endfunction
    wire [7:0] rx_data;
    wire rx_valid, rx_error, tx_busy;
    reg tx_start;
    reg [7:0] tx_data;
    uart_rx #(.CLOCK_HZ(CLOCK_HZ),.BAUD(BAUD)) u_rx
        (.clk(clk),.rst_n(rst_n),.rx_i(uart_rx_i),.data_o(rx_data),.valid_o(rx_valid),.error_o(rx_error));
    uart_tx #(.CLOCK_HZ(CLOCK_HZ),.BAUD(BAUD)) u_tx
        (.clk(clk),.rst_n(rst_n),.data_i(tx_data),.start_i(tx_start),.tx_o(uart_tx_o),.busy_o(tx_busy));
    wire key_up, key_down;
    key_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_up
        (.clk(clk),.rst_n(rst_n),.key_i(key_data[0]),.pressed_o(key_up));
    key_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_down
        (.clk(clk),.rst_n(rst_n),.key_i(key_data[1]),.pressed_o(key_down));
    reg [11:0] desired, transfer_value, command_target;
    reg transfer_request;
    wire transfer_busy;
    wire [11:0] applied;
    threshold_cdc u_threshold_cdc(
        .src_clk(clk),.src_rst_n(rst_n),.src_request_i(transfer_request),.src_value_i(transfer_value),
        .busy_o(transfer_busy),.applied_o(applied),.pixel_clk(pixel_clk),.pixel_rst_n(pixel_rst_n),
        .frame_blank_i(frame_blank_i),.pixel_value_o(threshold_pixel_o)
    );
    reg [3:0] rx_index, tx_index;
    reg [7:0] sequence_id, command, crc;
    reg [63:0] payload;
    reg [31:0] rx_timeout;
    reg waiting_apply, reply_busy;
    reg [7:0] wait_sequence, wait_command;
    reg [103:0] reply_shift;
    /* 10 ms 字节间超时：丢弃残帧，下一帧重新从 A5 5A 开始。 */
    localparam TIMEOUT_TICKS=CLOCK_HZ/100;

    task reply;
        input [7:0] seq, cmd, status;
        reg [63:0] body;
        reg [7:0] check;
        integer j;
        begin
            body={24'd0,8'h01,8'h01,4'b0,applied[11:8],applied[7:0],status};
            check=crc_next(crc_next(0,seq),cmd|8'h80);
            for(j=0;j<8;j=j+1) check=crc_next(check,body[j*8 +: 8]);
            reply_shift<={check,body,(cmd|8'h80),seq,16'h5aa5};
            reply_busy<=1; tx_index<=0;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            desired<=128; transfer_value<=128; transfer_request<=0; command_target<=128;
            rx_index<=0; sequence_id<=0; command<=0; payload<=0; crc<=0; rx_timeout<=0;
            waiting_apply<=0; wait_sequence<=0; wait_command<=0;
            tx_start<=0; tx_data<=0; reply_busy<=0; reply_shift<=0; tx_index<=0;
        end else begin
            transfer_request<=0; tx_start<=0;
            /* 同一寄存器集中写入；范围0..4095，两个键同时按下不修改。 */
            if (!waiting_apply) begin
                if (key_up && !key_down && desired!=4095) desired<=desired+1'b1;
                else if (key_down && !key_up && desired!=0) desired<=desired-1'b1;
            end
            if (!transfer_busy && !transfer_request && desired!=applied) begin
                transfer_value<=desired; transfer_request<=1;
            end
            if (waiting_apply && !transfer_busy && !transfer_request && applied==command_target) begin
                waiting_apply<=0;
                reply(wait_sequence,wait_command,0);
            end
            if (reply_busy && !tx_busy && !tx_start) begin
                tx_data<=reply_shift[7:0]; tx_start<=1; reply_shift<=reply_shift>>8;
                if (tx_index==12) reply_busy<=0;
                else tx_index<=tx_index+1'b1;
            end
            if (rx_error) begin rx_index<=0; rx_timeout<=0; end
            else if (rx_valid) begin
                rx_timeout<=0;
                case(rx_index)
                    0: if (rx_data==8'ha5) rx_index<=1;
                    1: if (rx_data==8'h5a) begin rx_index<=2; crc<=0; end
                       else if (rx_data!=8'ha5) rx_index<=0;
                    2: begin sequence_id<=rx_data; crc<=crc_next(0,rx_data); rx_index<=3; end
                    3: begin command<=rx_data; crc<=crc_next(crc,rx_data); rx_index<=4; end
                    12: begin
                        rx_index<=0;
                        /* stop-and-wait：处理或发送应答期间不接受额外命令。 */
                        if (!waiting_apply && !reply_busy && !tx_busy && !tx_start) begin
                            if (rx_data!=crc) reply(sequence_id,command,1);
                            else if (command==8'h01) begin
                                if (payload!=0) reply(sequence_id,command,2);
                                else reply(sequence_id,command,0);
                            end else if (command==8'h10) begin
                                if (payload[63:12]!=0) reply(sequence_id,command,2);
                                else begin
                                    desired<=payload[11:0]; command_target<=payload[11:0];
                                    waiting_apply<=1; wait_sequence<=sequence_id; wait_command<=command;
                                end
                            end else reply(sequence_id,command,3);
                        end
                    end
                    default: begin
                        payload[(rx_index-4)*8 +: 8]<=rx_data;
                        crc<=crc_next(crc,rx_data); rx_index<=rx_index+1'b1;
                    end
                endcase
            end else if (rx_index!=0) begin
                if (rx_timeout==TIMEOUT_TICKS-1) begin rx_index<=0; rx_timeout<=0; end
                else rx_timeout<=rx_timeout+1'b1;
            end
        end
    end
endmodule
