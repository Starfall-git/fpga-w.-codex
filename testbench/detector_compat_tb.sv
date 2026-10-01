`timescale 1ns/1ps
// v1.1 / 13: Every hidden activation and all six logits vs exported INT8 reference.
module detector_compat_tb;
    reg clk=0,rst=0,start=0;
    always #5 clk=~clk;
    wire [15:0] address;reg[7:0]data;
    reg [7:0] image[0:4095];
    reg [7:0] l0[0:8191],l1[0:4095],l2[0:1535],l3[0:511];
    reg [15:0] expected_scores[0:5];
    wire busy,done;wire[95:0]scores;wire[31:0]cycles;
    integer vector,index,checked=0;
    reg[7:0]expected;
    gesture_shared_cnn #(.WEIGHTS_FILE("src/cnn/rom/weights.hex"),.BIASES_FILE("src/cnn/rom/biases.hex"),.SHIFTS_FILE("src/cnn/rom/shifts.hex"))dut(.detect_i(1'b0),.clk(clk),.rst_n(rst),.start_i(start),.roi_addr_o(address),
        .roi_data_i(data),.busy_o(busy),.done_o(done),.scores_o(scores),.cycles_o(cycles));
    always @(posedge clk)data<=image[address];
    always @(posedge clk)if(rst && dut.state==8 && dut.layer<4)begin
        case(dut.layer)
            0:expected=l0[dut.output_index];1:expected=l1[dut.output_index];
            2:expected=l2[dut.output_index];3:expected=l3[dut.output_index];
        endcase
        if(dut.activated!==expected)$fatal(1,"V%0d L%0d index%0d got%0d expected%0d",vector,dut.layer,dut.output_index,dut.activated,expected);
        checked=checked+1;
    end
    initial begin
        repeat(5)@(negedge clk);rst=1;
        for(vector=0;vector<8;vector=vector+1)begin
            $readmemh($sformatf("ml/gesture/artifacts/vectors/input_%0d.hex",vector),image);
            $readmemh($sformatf("ml/gesture/artifacts/vectors/scores_%0d.hex",vector),expected_scores);
            $readmemh($sformatf("ml/gesture/artifacts/vectors/layer_%0d_0.hex",vector),l0);
            $readmemh($sformatf("ml/gesture/artifacts/vectors/layer_%0d_1.hex",vector),l1);
            $readmemh($sformatf("ml/gesture/artifacts/vectors/layer_%0d_2.hex",vector),l2);
            $readmemh($sformatf("ml/gesture/artifacts/vectors/layer_%0d_3.hex",vector),l3);
            @(negedge clk);start=1;@(negedge clk);start=0;
            wait(done);@(negedge clk);
            for(index=0;index<6;index=index+1)
                if(scores[index*16+:16]!==expected_scores[index])$fatal(1,"Score mismatch V%0d class%0d",vector,index);
            $display("VECTOR %0d PASS cycles=%0d",vector,cycles);
        end
        $display("PASS DETECTOR COMPAT: %0d hidden activations, 48 logits",checked);$finish;
    end
    initial begin #200000000;$fatal(1,"CNN timeout");end
endmodule
