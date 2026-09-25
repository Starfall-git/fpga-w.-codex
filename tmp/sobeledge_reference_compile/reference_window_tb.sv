`timescale 1ns/1ps
module reference_window_tb;
    reg clk=0, rst_n=0, hs=1, vs=1, de=0, valid=0;
    reg [71:0] pixels=0;
    wire [23:0] rgb;
    wire ho,vo,do_;
    always #5 clk=~clk;
    sobeledge_8d_window dut(
        .clk(clk),.rst_n(rst_n),.BINARY_OUTPUT(1'b1),.THRESHOLD(12'd128),
        .pixels_i(pixels),.hs_i(hs),.vs_i(vs),.de_i(de),
        .window_valid_i(valid),.rgb_o(rgb),.hs_o(ho),.vs_o(vo),.de_o(do_));
    task check(input [71:0] window, input [23:0] expected);
    begin
        @(negedge clk); pixels=window; de=1; valid=1;
        repeat(4) @(posedge clk);
        #1;
        if ({ho,vo,do_,rgb} !== {1'b1,1'b1,1'b1,expected})
            $fatal(1,"expected=%h actual=%h",expected,rgb);
    end
    endtask
    initial begin
        repeat(2) @(negedge clk); rst_n=1;
        check({9{8'd0}},24'h000000);
        check({8'd0,8'd0,8'd255,8'd0,8'd0,8'd255,
               8'd0,8'd0,8'd255},24'hffffff);
        /* One +100 at p13: G135=200, so Gmax/2=100. */
        check({8'd0,8'd0,8'd100,8'd0,8'd0,8'd0,
               8'd0,8'd0,8'd0},24'h646464);
        @(negedge clk); valid=0;
        repeat(4) @(posedge clk); #1;
        if (rgb !== 0) $fatal(1,"invalid border was not black");
        @(negedge clk); de=0;
        repeat(4) @(posedge clk); #1;
        if (do_ !== 0 || rgb !== 0) $fatal(1,"blanking failed");
        $display("PASS reference strength, 3x3 directions, valid and blanking");
        $finish;
    end
endmodule
