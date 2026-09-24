`timescale 1ns/1ps
/*
2026-09-21 V0.4 / 13~16：按键和 UART 阈值仲裁、固定帧协议、CRC8、硬件回读。
帧：A5 5A SEQ CMD DATA[0..7] CRC8，共13字节；CRC覆盖SEQ..DATA7，poly=07/init=00。
CMD 01=查询，10=设置阈值(uint16 LE，其余6字节0)；其余返回未实现。
应答CMD=原CMD|80；DATA={status,阈值低,阈值高,版本1,能力位,0,0,0}。
status 0成功/1CRC错误/2参数错误/3未实现；能力bit0表示动态阈值。
上位机一次只发送一个请求并等待应答。设置成功应答在像素域确认应用后发送。
串口设置等待期间忽略按键新事件，避免刚设置的值被覆盖；其余时间保留按键加减。
2026-09-22 V0.5 / 22：在以上V0.4基础上实现20/21/22几何命令及02分页回读，
TRANSFORM_ENABLE=1时能力位为0F。几何配置由DDR读出器帧准备完成后确认。
*/
module uart_image_control #(
    parameter CLOCK_HZ=96000000,
    parameter BAUD=115200,
    parameter DEBOUNCE_CYCLES=1920000,
    /* V0.5 / 22: geometry limits and capability switch for legacy regression. */
    parameter TRANSFORM_ENABLE=1, IMAGE_WIDTH=1280, IMAGE_HEIGHT=720
)(
    input wire clk, rst_n,
    input wire uart_rx_i,
    output wire uart_tx_o,
    input wire [1:0] key_data,
    input wire pixel_clk, pixel_rst_n, frame_blank_i,
    output wire [11:0] threshold_pixel_o,
    /* V0.6 / 25: pixel-domain runtime Sobel enable and binary polarity. */
    /* V0.9 / 44: bit2 is the frame-committed Median enable. */
    output wire enable_sobel_o, binary_output_o, enable_median_o,
    /* V0.5 / 20,22: mailbox held stable until DDR reader acknowledges frame commit. */
    output reg [97:0] geometry_o,
    output reg geometry_toggle_o,
    input wire geometry_ack_i,
    input wire [1:0] transform_faults_i
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
    /* V0.5: bit0 vertical / bit1 horizontal; GET_CONFIG(02) has four pages.
       Existing 01/10 and standard response remain wire-compatible with V1. */
    localparam [15:0] DEFAULT_W=IMAGE_WIDTH, DEFAULT_H=IMAGE_HEIGHT;
    localparam [97:0] DEFAULT_GEOMETRY={16'd1,16'd1,DEFAULT_H,DEFAULT_W,16'd0,16'd0,2'd0};
    /* V0.6 / 26~27: bit4 ISP controls, bit5 10%-500%, bit6 device defaults. */
    /* V0.9 / 44: capability bit7 advertises optional Median in both builds. */
    localparam [7:0] CAPABILITIES=TRANSFORM_ENABLE ? 8'hff : 8'hd1;
    reg [2:0] isp_target;
    wire [2:0] isp_applied, isp_pixel;
    reg isp_request, waiting_isp, waiting_default;
    wire isp_busy;
    threshold_cdc #(.WIDTH(3),.RESET_VALUE(0)) u_isp_cdc(
        .src_clk(clk),.src_rst_n(rst_n),.src_request_i(isp_request),.src_value_i(isp_target),
        .busy_o(isp_busy),.applied_o(isp_applied),.pixel_clk(pixel_clk),.pixel_rst_n(pixel_rst_n),
        .frame_blank_i(frame_blank_i),.pixel_value_o(isp_pixel));
    assign enable_sobel_o=isp_pixel[0];
    assign binary_output_o=!isp_pixel[1];
    assign enable_median_o=isp_pixel[2];
    reg [97:0] geometry_applied;
    reg geometry_ack_meta, geometry_ack_sync, waiting_geometry;
    reg [1:0] fault_meta, fault_sync;
    wire [15:0] gx=payload[15:0], gy=payload[31:16], gw=payload[47:32], gh=payload[63:48];
    wire [16:0] crop_right={1'b0,gx}+{1'b0,gw}, crop_bottom={1'b0,gy}+{1'b0,gh};
    wire [31:0] crop_scaled_w=gw*geometry_applied[81:66], crop_scaled_h=gh*geometry_applied[81:66];
    wire [31:0] zoom_scaled_w=geometry_applied[49:34]*gx, zoom_scaled_h=geometry_applied[65:50]*gx;
    /* 10 ms 字节间超时：丢弃残帧，下一帧重新从 A5 5A 开始。 */
    localparam TIMEOUT_TICKS=CLOCK_HZ/100;

    /* V0.5: shared framing task also supports command-specific configuration readback. */
    task reply_body;
        input [7:0] seq, cmd;
        input [63:0] body;
        reg [7:0] check;
        integer j;
        begin
            check=crc_next(crc_next(0,seq),cmd|8'h80);
            for(j=0;j<8;j=j+1) check=crc_next(check,body[j*8 +: 8]);
            reply_shift<={check,body,(cmd|8'h80),seq,16'h5aa5};
            reply_busy<=1; tx_index<=0;
        end
    endtask
    task reply;
        input [7:0] seq, cmd, status;
        begin
            /* V0.4 body had capability=01; V0.5 advertises only compiled functions. */
            /* V0.6: D5 contains applied ISP flags; D6/D7 remain zero. */
            /* V0.9 / 44: D5 bit2 reads back the applied Median state. */
            reply_body(seq,cmd,{16'd0,5'd0,isp_applied,CAPABILITIES,8'h01,4'b0,applied[11:8],applied[7:0],status});
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            desired<=128; transfer_value<=128; transfer_request<=0; command_target<=128;
            rx_index<=0; sequence_id<=0; command<=0; payload<=0; crc<=0; rx_timeout<=0;
            waiting_apply<=0; wait_sequence<=0; wait_command<=0;
            tx_start<=0; tx_data<=0; reply_busy<=0; reply_shift<=0; tx_index<=0;
            /* V0.5: initialize full-frame identity geometry and CDC state. */
            geometry_o<=DEFAULT_GEOMETRY; geometry_applied<=DEFAULT_GEOMETRY; geometry_toggle_o<=0;
            geometry_ack_meta<=0; geometry_ack_sync<=0; waiting_geometry<=0; fault_meta<=0; fault_sync<=0;
            isp_target<=0; isp_request<=0; waiting_isp<=0; waiting_default<=0;
        end else begin
            geometry_ack_meta<=geometry_ack_i; geometry_ack_sync<=geometry_ack_meta;
            fault_meta<=transform_faults_i; fault_sync<=fault_meta;
            transfer_request<=0; tx_start<=0;
            isp_request<=0;
            /* V0.6: default ACK waits for every registered feature; threshold is preserved.
               Future features must add their reset and completion here, not in GUI. */
            if(waiting_isp && !isp_request && !isp_busy && isp_applied==isp_target) begin
                waiting_isp<=0;
                if(!waiting_default) reply(wait_sequence,wait_command,0);
            end
            if(waiting_default && !waiting_isp && !waiting_geometry) begin
                waiting_default<=0; reply(wait_sequence,wait_command,0);
            end
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
            /* V0.5: do not acknowledge a desired value before DDR frame setup completes. */
            if(waiting_geometry && geometry_ack_sync==geometry_toggle_o) begin
                geometry_applied<=geometry_o; waiting_geometry<=0;
                if(!waiting_default) reply(wait_sequence,wait_command,0);
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
                        if (!waiting_apply && !waiting_geometry && !waiting_isp && !waiting_default && !reply_busy && !tx_busy && !tx_start) begin
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
                            end else if(command==8'h11 || command==8'h12) begin
                                /* V0.9 / 44: 11 sets {median,invert,sobel}; 12 clears all three. */
                                if((command==8'h11 && payload[63:3]!=0) || (command==8'h12 && payload!=0))
                                    reply(sequence_id,command,2);
                                else begin
                                    isp_target<=command==8'h12 ? 3'd0 : payload[2:0];
                                    isp_request<=1; waiting_isp<=1;
                                    wait_sequence<=sequence_id; wait_command<=command;
                                    if(command==8'h12) begin
                                        waiting_default<=1;
                                        if(TRANSFORM_ENABLE) begin
                                            geometry_o<=DEFAULT_GEOMETRY; geometry_toggle_o<=~geometry_toggle_o;
                                            waiting_geometry<=1;
                                        end
                                    end
                                end
                            end else if(TRANSFORM_ENABLE && command==8'h02) begin
                                /* Query response: status,page,6-byte data. Invalid request returns status2. */
                                if(payload[63:2]!=0) reply_body(sequence_id,command,{48'd0,payload[7:0],8'd2});
                                else case(payload[1:0])
                                    0: reply_body(sequence_id,command,{32'd0,6'd0,fault_sync,6'd0,geometry_applied[1:0],8'd0,8'd0});
                                    1: reply_body(sequence_id,command,{16'd0,geometry_applied[33:2],8'd1,8'd0});
                                    2: reply_body(sequence_id,command,{16'd0,geometry_applied[65:34],8'd2,8'd0});
                                    3: reply_body(sequence_id,command,{16'd0,geometry_applied[97:66],8'd3,8'd0});
                                endcase
                            end else if(TRANSFORM_ENABLE && (command==8'h20 || command==8'h21 || command==8'h22)) begin
                                /* V0.5: reject overflow/out-of-image/zero-area results before publishing. */
                                if((command==8'h20 && payload[63:2]!=0) ||
                                   (command==8'h21 && (gw==0 || gh==0 || crop_right>IMAGE_WIDTH || crop_bottom>IMAGE_HEIGHT ||
                                      crop_scaled_w<geometry_applied[97:82] || crop_scaled_h<geometry_applied[97:82])) ||
                                   /* V0.6: old 1..16 and 0.25..4 limits replaced by uint16 rational 0.1..5. */
                                   (command==8'h22 && (payload[63:32]!=0 || gx==0 || gy==0 ||
                                      {16'd0,gx}>({16'd0,gy}*5) || {16'd0,gy}>({16'd0,gx}*10) ||
                                      zoom_scaled_w<gy || zoom_scaled_h<gy))) reply(sequence_id,command,2);
                                else begin
                                    geometry_o<=geometry_applied;
                                    case(command)
                                        8'h20: geometry_o[1:0]<=payload[1:0];
                                        8'h21: geometry_o[65:2]<=payload;
                                        8'h22: geometry_o[97:66]<=payload[31:0];
                                    endcase
                                    geometry_toggle_o<=~geometry_toggle_o; waiting_geometry<=1;
                                    wait_sequence<=sequence_id; wait_command<=command;
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
