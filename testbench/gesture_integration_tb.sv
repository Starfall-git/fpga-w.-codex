`timescale 1ns/1ps
// v1.1 / 24: Real dual-clock ROI -> CNN -> result path, without forced internals.
module gesture_integration_tb;
    reg clk=0,pclk=0,rst=0,en=0,fv=0,pv=0;
    reg [7:0] gray=0;
    always #5.208 clk=~clk;
    always #6.734 pclk=~pclk;
    wire [7:0] flags,cid;
    wire [15:0] margin,frame;
    wire [31:0] cycles;
    reg [7:0] image[0:4095];
    reg [15:0] golden[0:5],threshold[0:0];
    integer x,y,n,k,best,second,best_id,value;
    gesture_pipeline dut(.clk(clk),.rst_n(rst),.enable_i(en),
        .pixel_clk(pclk),.frame_i(fv),.valid_i(pv),.gray_i(gray),
        .flags_o(flags),.class_o(cid),.margin_o(margin),.frame_o(frame),.cycles_o(cycles));
    initial begin
        $readmemh("ml/gesture/artifacts/vectors/input_0.hex",image);
        $readmemh("ml/gesture/artifacts/vectors/scores_0.hex",golden);
        $readmemh("src/cnn/rom/threshold.hex",threshold);
        best=-32768;second=-32768;best_id=0;
        for(k=0;k<6;k=k+1)begin
            value=$signed(golden[k]);
            if(value>best)begin second=best;best=value;best_id=k;end
            else if(value>second)second=value;
        end
        repeat(10)@(negedge clk);rst=1;en=1;
        repeat(10)@(negedge pclk);
        for(n=1;n<=2;n=n+1)begin
            fv=1;repeat(5)@(negedge pclk);
            for(y=0;y<720;y=y+1)begin
                for(x=0;x<1280;x=x+1)begin
                    pv=1;
                    if(x>=384 && x<896 && y>=104 && y<616)
                        gray=image[((y-104)/8)*64+(x-384)/8];
                    else gray=8'd128;
                    @(negedge pclk);
                end
                pv=0;repeat(4)@(negedge pclk);
            end
            fv=0;pv=0;
            wait(frame==n);repeat(5)@(negedge clk);
            for(k=0;k<6;k=k+1)
                if(dut.scores[k*16+:16]!==golden[k])$fatal(1,"Integrated score mismatch frame%0d class%0d",n,k);
            if(cycles!=1462290)$fatal(1,"Unexpected compute cycles");
            if(n==1 && flags[2])$fatal(1,"Single result accepted");
            if(n==2 && best_id<5 && best-second>=threshold[0])begin
                if(!flags[2] || cid!=best_id || margin!=best-second)$fatal(1,"Confirmed result mismatch");
            end else if(flags[2])$fatal(1,"Rejected result presented as valid");
            repeat(10)@(negedge pclk);
        end
        en=0;repeat(5)@(negedge clk);
        if(flags[2] || cid!=255)$fatal(1,"Disable did not clear result");
        $display("PASS GESTURE INTEGRATION: two real frames, CDC, ROI, CNN, logits, confirmation, disable");$finish;
    end
    initial begin #100000000;$fatal(1,"Integration timeout");end
endmodule
