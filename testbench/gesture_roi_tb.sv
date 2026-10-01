`timescale 1ns/1ps
// v1.1 / 12: Independent 8x8 sum, CDC ownership, skipped/partial/disabled frames.
module gesture_roi_tb;
    reg pclk=0,clk=0,rst=0,en=0,ack=0,frame=0,valid=0;
    reg [7:0] gray=0;
    reg [11:0] address=0;
    wire [7:0] data;
    wire req;wire[15:0]id;
    always #7 pclk=~pclk;
    always #5 clk=~clk;
    gesture_roi #(.IMAGE_WIDTH(640),.ROI_X(64),.ROI_Y(0)) dut(
        .pixel_clk(pclk),.pixel_rst_n(rst),.frame_i(frame),.valid_i(valid),.gray_i(gray),
        .enable_i(en),.ack_i(ack),.request_o(req),.frame_id_o(id),
        .read_clk(clk),.read_addr_i(address),.read_data_o(data));
    function integer sample(input integer x,y,mode);
        if(mode==1)sample=255;else if(mode==2)sample=0;else sample=(3*x+5*y)&255;
    endfunction
    task send_frame(input integer mode,rows);
        integer x,y;
        begin
            @(negedge pclk);frame=1;valid=0;
            repeat(8)@(negedge pclk);
            for(y=0;y<rows;y=y+1)begin
                for(x=0;x<640;x=x+1)begin valid=1;gray=sample(x,y,mode);@(negedge pclk);end
                valid=0;repeat(5)@(negedge pclk);
            end
            frame=0;valid=0;repeat(10)@(negedge pclk);
        end
    endtask
    task check(input integer mode);
        integer x,y,a,b,sum,expected;
        begin
            for(y=0;y<64;y=y+1)for(x=0;x<64;x=x+1)begin
                sum=0;
                for(a=0;a<8;a=a+1)for(b=0;b<8;b=b+1)sum=sum+sample(64+x*8+b,y*8+a,mode);
                expected=(sum+32)/64;
                @(negedge clk);address=y*64+x;
                repeat(2)@(negedge clk);
                if(data!==expected[7:0])$fatal(1,"ROI mismatch %0d,%0d got%0d expected%0d",x,y,data,expected);
            end
        end
    endtask
    initial begin
        repeat(5)@(negedge clk);rst=1;en=1;repeat(10)@(negedge pclk);
        send_frame(0,512);if(req!==1)$fatal(1,"No completed ROI");check(0);
        send_frame(1,512);if(req!==1)$fatal(1,"Overwrote owned ROI");check(0);
        ack=req;repeat(8)@(negedge pclk);
        send_frame(1,100);if(req!==ack)$fatal(1,"Partial frame committed");
        send_frame(1,512);if(req===ack)$fatal(1,"No second ROI");check(1);
        ack=req;en=0;repeat(8)@(negedge pclk);send_frame(2,512);
        if(req!==ack)$fatal(1,"Disabled capture committed");check(1);
        en=1;repeat(8)@(negedge pclk);send_frame(2,512);check(2);
        $display("PASS GESTURE ROI: 4x4096 pixels, immutable ownership, partial/disable/restart");$finish;
    end
    initial begin #100000000;$fatal(1,"timeout");end
endmodule
