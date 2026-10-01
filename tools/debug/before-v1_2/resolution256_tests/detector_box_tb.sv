`timescale 1ns/1ps
// v1.2 / 17: Independent fixed expectations for score gating and image corners.
module detector_box_tb;
    reg clk=0,rst=0,start=0,valid=0;
    always #5 clk=~clk;
    reg [3:0]gx=0,gy=0;reg[2:0]channel=0;reg signed[15:0]value=0;
    wire hit;wire[10:0]x,y;wire[3:0]block;wire signed[15:0]score;
    gesture_box_decoder #(.THRESHOLD_FILE("test_threshold.hex"))dut(.clk(clk),.rst_n(rst),.start_i(start),
        .valid_i(valid),.x_i(gx),.y_i(gy),.channel_i(channel),.value_i(value),
        .valid_o(hit),.roi_x_o(x),.roi_y_o(y),.block_o(block),.best_score_o(score));
    task candidate(input[3:0]cx,cy,input signed[15:0]obj,dx,dy,w,h);
        begin
            @(negedge clk);valid=1;gx=cx;gy=cy;channel=0;value=obj;
            @(negedge clk);channel=1;value=dx;
            @(negedge clk);channel=2;value=dy;
            @(negedge clk);channel=3;value=w;
            @(negedge clk);channel=4;value=h;
            @(negedge clk);valid=0;
        end
    endtask
    task clear;
        begin @(negedge clk);start=1;@(negedge clk);start=0;end
    endtask
    initial begin
        repeat(5)@(negedge clk);rst=1;clear();if(hit)$fatal(1,"empty detector valid");
        candidate(0,0,1000,128,128,16,16);
        if(!hit || x!=0 || y!=0 || block!=2)$fatal(1,"top-left clipping");
        candidate(15,8,1500,128,128,16,16);
        if(!hit || x!=1152 || y!=592 || block!=2 || score!=1500)$fatal(1,"bottom-right clipping");
        candidate(7,4,2000,128,128,-1,0);
        if(score!=1500)$fatal(1,"invalid box shadowed valid candidate");
        clear();candidate(7,4,1000,256,128,64,64);
        if(!hit || x!=384 || y!=104 || block!=8)$fatal(1,"size/center decoding");
        clear();candidate(7,4,-100,128,128,64,64);if(hit)$fatal(1,"low confidence accepted");
        clear();if(hit)$fatal(1,"reset retained detection");
        $display("PASS DETECTOR BOX: corner clipping, scaling, invalid boxes, threshold and reset");$finish;
    end
endmodule
