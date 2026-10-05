`timescale 1ns/1ps
module cnn_gray_snapshot_tb;
    reg cam_clk=0,cpu_clk=0,rst=0,cpu_rst=0,fv=0,pv=0;
    always #7 cam_clk=~cam_clk;
    always #5 cpu_clk=~cpu_clk;
    reg [7:0] gray=0;
    reg [15:0] addr=0;
    reg sel=0,en=0,wr=0;
    reg [31:0] wdata=0;
    wire [31:0] rdata;
    wire ready,err;
    integer word_index,j,px,py,checks=0;
    reg [31:0] value,expected,first_word;
    cnn_gray_snapshot dut(.cam_clk(cam_clk),.cam_rst_n(rst),.frame_valid(fv),
        .pixel_valid(pv),.gray(gray),.PCLK(cpu_clk),.PRESETn(cpu_rst),.PADDR(addr),
        .PSEL(sel),.PENABLE(en),.PWRITE(wr),.PWDATA(wdata),.PREADY(ready),
        .PSLVERROR(err),.PRDATA(rdata));
    function [7:0] pattern(input integer x,input integer y,input integer frame_id);
        pattern=(3*x+5*y+17*frame_id)&255;
    endfunction
    task apb(input bit write,input [15:0] address,input [31:0] data,input bit expected_error,output [31:0] readback);
        @(negedge cpu_clk);sel=1;en=0;wr=write;addr=address;wdata=data;
        @(negedge cpu_clk);en=1;
        @(posedge cpu_clk);
        if(!ready || err!==expected_error) $fatal(1,"APB mismatch addr=%h err=%b expected=%b",address,err,expected_error);
        readback=rdata;checks=checks+1;
        @(negedge cpu_clk);sel=0;en=0;wr=0;
    endtask
    task frame(input integer id,input integer rows);
        @(negedge cam_clk);fv=1;pv=0;
        repeat(5) @(negedge cam_clk);
        for(integer y=0;y<rows;y=y+1) begin
            for(integer x=0;x<1280;x=x+1) begin
                pv=1;gray=pattern(x,y,id);@(negedge cam_clk);
            end
            pv=0;repeat(4) @(negedge cam_clk);
        end
        fv=0;pv=0;repeat(8) @(negedge cam_clk);
    endtask
    task check_image(input integer id);
        for(integer w=0;w<1024;w=w+1) begin
            expected=0;
            for(integer b=0;b<4;b=b+1) begin
                px=388+8*((w*4+b)%64);py=108+8*((w*4+b)/64);
                expected[b*8+:8]=pattern(px,py,id);
            end
            apb(0,16'h1000+w*4,0,0,value);
            if(value!==expected) $fatal(1,"Pixel/packing mismatch word=%0d got=%h expected=%h",w,value,expected);
        end
    endtask
    initial begin
        #80;rst=1;cpu_rst=1;repeat(8) @(posedge cpu_clk);
        apb(0,16'h0040,0,0,value);if(value!==32'h43415031) $fatal(1,"ABI");
        apb(0,16'h1000,0,1,value);
        apb(1,16'h0048,2,1,value);
        apb(1,16'h0048,1,0,value);
        repeat(8) @(posedge cam_clk);
        fork
            frame(1,720);
            begin repeat(20) @(posedge cam_clk);apb(1,16'h0048,1,1,value);end
        join
        repeat(8) @(posedge cpu_clk);
        apb(0,16'h0044,0,0,value);if(value!==1) $fatal(1,"Not ready");
        apb(0,16'h0058,0,0,value);if(value!==4096) $fatal(1,"Incomplete image accepted");
        check_image(1);
        apb(0,16'h1000,0,0,first_word);
        frame(2,720);
        apb(0,16'h1000,0,0,value);if(value!==first_word) $fatal(1,"Bank overwritten without request");
        apb(1,16'h1000,0,1,value);
        apb(0,16'h1001,0,1,value);
        apb(1,16'h0048,1,0,value);repeat(8) @(posedge cam_clk);
        frame(3,100);repeat(8) @(posedge cpu_clk);
        apb(0,16'h0044,0,0,value);if(value!==4) $fatal(1,"Truncated frame accepted");
        apb(0,16'h1000,0,1,value);
        // Reset both ownership domains, then confirm stale RAM is inaccessible.
        #3;rst=0;#41;rst=1;repeat(8) @(posedge cpu_clk);
        apb(0,16'h1000,0,1,value);
        apb(1,16'h0048,1,0,value);repeat(8) @(posedge cam_clk);
        frame(4,720);repeat(8) @(posedge cpu_clk);check_image(4);
        // A request in the middle of a frame must wait for the next frame.
        fork
            frame(5,720);
            begin repeat(10000) @(posedge cam_clk);apb(1,16'h0048,1,0,value);end
        join
        apb(0,16'h0044,0,0,value);if(value!==2) $fatal(1,"Mid-frame capture admitted");
        frame(6,720);repeat(8) @(posedge cpu_clk);check_image(6);
        apb(1,16'h0048,1,0,value);repeat(8) @(posedge cam_clk);
        fork
            frame(7,720);
            begin repeat(200000) @(posedge cam_clk);#3;cpu_rst=0;#41;cpu_rst=1;end
        join
        apb(0,16'h0044,0,0,value);if(value!==0) $fatal(1,"CPU reset retained ownership");
        apb(0,16'h1000,0,1,value);
        apb(1,16'h0048,1,0,value);repeat(8) @(posedge cam_clk);
        frame(8,720);repeat(8) @(posedge cpu_clk);check_image(8);
        $display("PASS CNN gray snapshot: %0d APB checks, four images, freeze, truncation, mid-frame request, CPU-only reset",checks);
        $finish;
    end
    initial begin #150000000;$fatal(1,"timeout");end
endmodule
