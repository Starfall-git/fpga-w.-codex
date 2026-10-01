`timescale 1ns/1ps
// v1.1 / 19: Scheduler unit test with controlled inference-completion interface.
module gesture_pipeline_tb;
    reg clk=0,pclk=0,rst=0,en=0;
    always #5 clk=~clk;always #7 pclk=~pclk;
    wire[7:0]flags,cid;wire[15:0]margin,frame;wire[31:0]cycles;
    reg req=0,done=0;reg[95:0]scores=0;reg[15:0]source_frame=0;
    gesture_pipeline #(.CLOCK_HZ(1000)) dut(.clk(clk),.rst_n(rst),.enable_i(en),
        .pixel_clk(pclk),.frame_i(1'b0),.valid_i(1'b0),.gray_i(8'd0),
        .flags_o(flags),.class_o(cid),.margin_o(margin),.frame_o(frame),.cycles_o(cycles));
    task result(input integer label,input[15:0]identifier);
        begin
            @(negedge clk);source_frame=identifier;req=~req;scores=0;
            scores[label*16+:16]=16'd10000;
            repeat(8)@(negedge clk);
            if(!dut.active)$fatal(1,"scheduler missed immutable ROI");
            done=1;@(negedge clk);done=0;repeat(3)@(negedge clk);
            if(dut.acknowledge!==req || frame!==identifier)$fatal(1,"ownership/frame ID mismatch");
        end
    endtask
    initial begin
        force dut.request=req;force dut.roi_frame=source_frame;
        force dut.done=done;force dut.scores=scores;force dut.busy=0;
        repeat(5)@(negedge clk);rst=1;en=1;
        result(0,1);if(flags[2] || cid!=255)$fatal(1,"accepted one unstable result");
        result(0,2);if(!flags[2] || cid!=0)$fatal(1,"stable result rejected");
        result(4,3);if(flags[2])$fatal(1,"gesture change not debounced");
        result(4,4);if(!flags[2] || cid!=4)$fatal(1,"second stable class rejected");
        repeat(510)@(negedge clk);if(flags[2] || !flags[4] || cid!=255)$fatal(1,"stale result not invalidated");
        result(4,5);if(flags[2])$fatal(1,"stale repeat history reused");
        result(5,6);if(flags[2])$fatal(1,"negative class accepted");
        result(0,7);result(0,8);en=0;repeat(5)@(negedge clk);
        if(flags[0] || flags[2] || cid!=255)$fatal(1,"disabled output remains valid");
        en=1;result(0,9);if(flags[2])$fatal(1,"restart reused old confidence");
        $display("PASS GESTURE PIPELINE: mailbox, two-frame confirmation, unknown, expiry, disable/restart");$finish;
    end
    initial begin #1000000;$fatal(1,"pipeline timeout");end
endmodule
