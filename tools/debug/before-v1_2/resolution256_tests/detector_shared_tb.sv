`timescale 1ns/1ps
// v1.2 / 18: All shared-engine hidden values/head outputs vs integer reference.
module detector_shared_tb;
    reg clk=0,rst=0,start=0,detect=0;
    always #5 clk=~clk;
    wire[13:0]addr;reg[7:0]data;reg[7:0]image[0:9215];
    reg[7:0]l0[0:18431],l1[0:9215],l2[0:3455],l3[0:4607];
    reg[15:0]head[0:719],scores_expected[0:5];
    wire busy,done,dv;wire[95:0]scores;wire[31:0]cycles;
    wire[3:0]dx,dy;wire[2:0]dc;wire signed[15:0]value;
    integer mode,n,k,checked=0,head_checked=0;reg[7:0]expected;
    gesture_shared_cnn dut(.clk(clk),.rst_n(rst),.start_i(start),.detect_i(detect),
        .roi_addr_o(addr),.roi_data_i(data),.busy_o(busy),.done_o(done),.scores_o(scores),.cycles_o(cycles),
        .detect_valid_o(dv),.detect_x_o(dx),.detect_y_o(dy),.detect_channel_o(dc),.detect_value_o(value));
    always @(posedge clk)data<=image[addr];
    always @(posedge clk)if(rst)begin
        if(dut.state==8 && dut.layer<4)begin
            case(dut.layer)
                0:expected=l0[dut.output_index];1:expected=l1[dut.output_index];
                2:expected=l2[dut.output_index];3:expected=l3[dut.output_index];
            endcase
            if(dut.activated!==expected)$fatal(1,"mode%0d vector%0d layer%0d index%0d got%0d exp%0d",mode,n,dut.layer,dut.output_index,dut.activated,expected);
            checked=checked+1;
        end
        if(dv)begin
            if(value!==head[(dy*16+dx)*5+dc])$fatal(1,"Detector head mismatch at %0d,%0d channel%0d",dx,dy,dc);
            head_checked=head_checked+1;
        end
    end
    initial begin
        repeat(5)@(negedge clk);rst=1;
        // Run classifier again after detector to catch mode/bank leakage.
        for(mode=0;mode<3;mode=mode+1)begin
            detect=(mode==1);
            for(n=0;n<(detect?6:8);n=n+1)begin
                if(detect)begin
                    $readmemh($sformatf("ml/detector/artifacts/vectors/input_%0d.hex",n),image,0,9215);
                    $readmemh($sformatf("ml/detector/artifacts/vectors/head_%0d.hex",n),head);
                    $readmemh($sformatf("ml/detector/artifacts/vectors/layer_%0d_0.hex",n),l0,0,18431);
                    $readmemh($sformatf("ml/detector/artifacts/vectors/layer_%0d_1.hex",n),l1,0,9215);
                    $readmemh($sformatf("ml/detector/artifacts/vectors/layer_%0d_2.hex",n),l2,0,3455);
                    $readmemh($sformatf("ml/detector/artifacts/vectors/layer_%0d_3.hex",n),l3,0,4607);
                end else begin
                    $readmemh($sformatf("ml/gesture/artifacts/vectors/input_%0d.hex",n),image,0,4095);
                    $readmemh($sformatf("ml/gesture/artifacts/vectors/scores_%0d.hex",n),scores_expected);
                    $readmemh($sformatf("ml/gesture/artifacts/vectors/layer_%0d_0.hex",n),l0,0,8191);
                    $readmemh($sformatf("ml/gesture/artifacts/vectors/layer_%0d_1.hex",n),l1,0,4095);
                    $readmemh($sformatf("ml/gesture/artifacts/vectors/layer_%0d_2.hex",n),l2,0,1535);
                    $readmemh($sformatf("ml/gesture/artifacts/vectors/layer_%0d_3.hex",n),l3,0,511);
                end
                @(negedge clk);start=1;@(negedge clk);start=0;wait(done);repeat(2)@(negedge clk);
                if(!detect)for(k=0;k<6;k=k+1)if(scores[k*16+:16]!==scores_expected[k])$fatal(1,"Classifier score mismatch");
                $display("MODE%0d VECTOR%0d PASS cycles=%0d",mode,n,cycles);
            end
        end
        if(head_checked!=4320)$fatal(1,"Missing detector outputs");
        $display("PASS DETECTOR SHARED: %0d hidden values, %0d detection outputs, 96 class logits, mode switches",checked,head_checked);$finish;
    end
    initial begin #700000000;$fatal(1,"shared timeout");end
endmodule
