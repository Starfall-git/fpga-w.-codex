`timescale 1ns/1ps
/* V0.5: Python-generated wire packets -> UART -> real DDR-reader commit -> UART readback. */
module uart_geometry_tb;
    reg clk=0, pixel_clk=0, rst=0, rx=1, vs=1;
    always #5.208333 clk=~clk;
    always #6.720430 pixel_clk=~pixel_clk;
    localparam real BIT=104.16666;
    wire tx, gt, ga, enabled, polarity, median_enabled;
    wire [97:0] geometry;
    wire [11:0] threshold;
    wire [1:0] faults;
    uart_image_control #(.CLOCK_HZ(1000000),.BAUD(100000),.DEBOUNCE_CYCLES(4)) control(
        .clk(clk),.rst_n(rst),.uart_rx_i(rx),.uart_tx_o(tx),.key_data(2'b11),
        .pixel_clk(pixel_clk),.pixel_rst_n(rst),.frame_blank_i(!vs),.threshold_pixel_o(threshold),
        .enable_sobel_o(enabled),.binary_output_o(polarity),.enable_median_o(median_enabled),
        .geometry_o(geometry),.geometry_toggle_o(gt),.geometry_ack_i(ga),.transform_faults_i(faults));
    wire [31:0] addr;
    wire [7:0] len;
    wire av, rr;
    reg active=0, rv=0, rl=0;
    integer count=0;
    axi_transform_reader reader(.axi_clk(clk),.axi_reset(!rst),.frame_index_i(2'd1),.frame_switch_o(),
        .araddr_o(addr),.arlen_o(len),.arvalid_o(av),.arready_i(!active),
        .rdata_i(128'd0),.rresp_i(2'd0),.rlast_i(rl),.rvalid_i(rv),.rready_o(rr),
        .pixel_clk(pixel_clk),.vs_i(vs),.request_i(1'b0),.pixel_o(),
        .geometry_i(geometry),.geometry_toggle_i(gt),.geometry_ack_o(ga),.faults_o(faults));
    always @(posedge clk) begin
        if(!rst) begin active<=0; rv<=0; count<=0; end
        else begin
            if(av && !active) begin active<=1; count<=len+1; end
            if(rv && rr) begin rv<=0; if(rl) active<=0; end
            if(active && (!rv || rr) && count>0) begin rv<=1; rl<=count==1; count<=count-1; end
        end
    end
    initial begin
        wait(rst);
        forever begin
            repeat(2000) @(negedge pixel_clk); vs=0;
            repeat(1000) @(negedge pixel_clk); vs=1;
            repeat(5000) @(negedge pixel_clk);
        end
    end
    reg [7:0] response[0:8191];
    integer received=0, bit_index;
    reg [7:0] byte_value;
    initial forever begin
        @(negedge tx); #(BIT/2);
        if(tx!==0) $fatal(1,"TX start");
        for(bit_index=0;bit_index<8;bit_index=bit_index+1) begin #BIT; byte_value[bit_index]=tx; end
        #BIT;
        if(tx!==1) $fatal(1,"TX stop");
        response[received]=byte_value; received=received+1;
    end
    task send_byte(input [7:0] value);
        integer b;
        begin rx=0; #BIT; for(b=0;b<8;b=b+1) begin rx=value[b]; #BIT; end rx=1; #BIT; end
    endtask
    integer f, number, n, b, scan;
    reg [103:0] command, expected;
    initial begin
        f=$fopen("packets.txt","r"); scan=$fscanf(f,"%d",number);
        #103; rst=1; #1000;
        for(n=0;n<number;n=n+1) begin
            scan=$fscanf(f,"%h %h",command,expected);
            for(b=0;b<13;b=b+1) send_byte(command[b*8+:8]);
            wait(received>=(n+1)*13);
            for(b=0;b<13;b=b+1)
                if(response[n*13+b]!==expected[b*8+:8]) $fatal(1,"Packet %0d byte%0d expected%h got%h",n,b,expected[b*8+:8],response[n*13+b]);
            /* V0.6: reply flags must match actual pixel-domain runtime ports. */
            if(command[31:24]==8'h11 || command[31:24]==8'h12)
            /* V0.9 / 46: ACK includes the applied Median bit after pixel blank. */
                if(enabled!==expected[72] || polarity!==!expected[73] || median_enabled!==expected[74])
                    $fatal(1,"ISP applied ports mismatch");
            #(BIT*3);
        end
        $display("PASS UART GEOMETRY: %0d Python wire packets, real DDR frame commit and actual configuration readback",number);
        $finish;
    end
    initial begin #20000000; $fatal(1,"UART geometry timeout"); end
endmodule
