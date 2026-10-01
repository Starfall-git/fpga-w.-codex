`timescale 1ns/1ps
// v1.2 / 20: Four unforced camera frames through detection and dynamic cropping.
module detector_auto_tb;
    reg clk=0,pc=0,rst=0,en=0,fv=0,pv=0;reg[7:0]gray=0;
    always #5.208 clk=~clk;always #6.734 pc=~pc;
    wire[7:0]flags,cid;wire[15:0]margin,frame,rx,ry,side;wire[31:0]cycles;
    reg[7:0]image[0:36863];reg[15:0]head[0:2879],scores[0:5],info[0:3];
    integer n,x,y,k,outputs=0;
    gesture_auto_pipeline dut(.clk(clk),.rst_n(rst),.enable_i(en),.pixel_clk(pc),.frame_i(fv),.valid_i(pv),.gray_i(gray),
        .flags_o(flags),.class_o(cid),.margin_o(margin),.frame_o(frame),.cycles_o(cycles),.roi_x_o(rx),.roi_y_o(ry),.roi_side_o(side));
    always @(posedge clk)if(dut.dv)begin
        if(dut.value_out!==head[(dut.dy*32+dut.dx)*5+dut.dc])$fatal(1,"Full frame detection output differs");
        outputs=outputs+1;
    end
    initial begin
        $readmemh("ml/detector/artifacts/vectors/auto_frame.hex",image);
        $readmemh("ml/detector/artifacts/vectors/auto_head.hex",head);
        $readmemh("ml/detector/artifacts/vectors/auto_scores.hex",scores);
        $readmemh("ml/detector/artifacts/vectors/auto_info.hex",info);
        repeat(10)@(negedge pc);rst=1;en=1;repeat(10)@(negedge pc);
        for(n=1;n<=4;n=n+1)begin
            fv=1;repeat(8)@(negedge pc);
            for(y=0;y<720;y=y+1)begin
                for(x=0;x<1280;x=x+1)begin
                    pv=1;gray=image[(y/5)*256+x/5];@(negedge pc);
                end
                pv=0;repeat(4)@(negedge pc);
            end
            fv=0;pv=0;
            wait(frame==n);repeat(10)@(negedge clk);
            if(rx!==info[0] || ry!==info[1] || side!==info[2])$fatal(1,"ROI/frame association differs");
            if(n%2==0)begin
                for(k=0;k<6;k=k+1)if(dut.scores[k*16+:16]!==scores[k])$fatal(1,"Adaptive crop classifier differs");
                if(n==2 && flags[2])$fatal(1,"Single classification accepted");
                if(n==4 && (!flags[2] || cid!==info[3][7:0]))$fatal(1,"Stable gesture not confirmed");
            end
            repeat(12)@(negedge pc);
            $display("AUTO FRAME%0d PASS roi=(%0d,%0d,%0d) cycles=%0d",n,rx,ry,side,cycles);
        end
        if(outputs!=5760)$fatal(1,"Missing detection head outputs");
        en=0;repeat(8)@(negedge clk);
        if(flags[2] || cid!=255 || side!=0)$fatal(1,"Disable retains stale output");
        $display("PASS DETECTOR AUTO: camera, full-frame CNN, adaptive ROI, classification, confirmation, disable");$finish;
    end
    initial begin #400000000;$fatal(1,"automatic pipeline timeout");end
endmodule
