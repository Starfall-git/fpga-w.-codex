`timescale 1ns/1ps
/* 2026-09-18 V0.3 新增：逐拍比较独立 Python 图像参考模型及全部同步信号。
   同时覆盖二值、灰度、阈值边界、旁路和高有效 VS。 */
/* V0.4 / 18：阈值由参数改为输入端口，测试向端口提供对应数值。 */
module video_processing_tb;
    parameter WIDTH = 8;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0, hs = 1, vs = 0, de = 0;
    reg [23:0] rgb = 0;
    wire [23:0] binary_rgb, strength_rgb, zero_rgb, max_rgb, bypass_rgb, high_rgb;
    wire bh, bv, bd, sh, sv, sd, zh, zv, zd, mh, mv, md, ph, pv, pd, hh, hv, hd;
    video_processing #(.IMAGE_WIDTH(WIDTH)) binary_dut
        (clk,rst_n,12'd128,rgb,hs,vs,de,binary_rgb,bh,bv,bd);
    video_processing #(.IMAGE_WIDTH(WIDTH),.SOBEL_BINARY(0)) strength_dut
        (clk,rst_n,12'd128,rgb,hs,vs,de,strength_rgb,sh,sv,sd);
    video_processing #(.IMAGE_WIDTH(WIDTH)) zero_dut
        (clk,rst_n,12'd0,rgb,hs,vs,de,zero_rgb,zh,zv,zd);
    video_processing #(.IMAGE_WIDTH(WIDTH)) max_dut
        (clk,rst_n,12'd2047,rgb,hs,vs,de,max_rgb,mh,mv,md);
    video_processing #(.IMAGE_WIDTH(WIDTH),.ENABLE_SOBEL(0)) bypass_dut
        (clk,rst_n,12'd128,rgb,hs,vs,de,bypass_rgb,ph,pv,pd);
    video_processing #(.IMAGE_WIDTH(WIDTH),.VS_ACTIVE(1'b1)) high_dut
        (clk,rst_n,12'd128,rgb,hs,~vs,de,high_rgb,hh,hv,hd);

    integer fd, count, n = 0;
    reg ri, hi, vi, di, eh, ev, ed;
    reg [23:0] pixel, eb, es, ez;
    reg [2047:0] filename;
    initial begin
        if (!$value$plusargs("VECTORS=%s",filename)) $fatal(1,"VECTORS missing");
        fd = $fopen(filename,"r");
        if (!fd) $fatal(1,"Cannot open vectors");
        while (!$feof(fd)) begin
            count = $fscanf(fd,"%h %h %h %h %h %h %h %h %h %h %h\n",
                            ri,hi,vi,di,pixel,eh,ev,ed,eb,es,ez);
            if (count == 11) begin
                @(negedge clk);
                rst_n=ri; hs=hi; vs=vi; de=di; rgb=pixel;
                @(posedge clk); #1;
                if ({bh,bv,bd,binary_rgb} !== {eh,ev,ed,eb})
                    $fatal(1,"binary cycle %0d expected %h actual %h",n,{eh,ev,ed,eb},{bh,bv,bd,binary_rgb});
                if ({sh,sv,sd,strength_rgb} !== {eh,ev,ed,es})
                    $fatal(1,"strength cycle %0d expected %h actual %h",n,{eh,ev,ed,es},{sh,sv,sd,strength_rgb});
                if ({zh,zv,zd,zero_rgb} !== {eh,ev,ed,ez}) $fatal(1,"threshold zero cycle %0d",n);
                if ({mh,mv,md,max_rgb} !== {eh,ev,ed,24'd0}) $fatal(1,"threshold max cycle %0d",n);
                if ({hh,hv,hd,high_rgb} !== {eh,~ev,ed,eb}) $fatal(1,"VS polarity cycle %0d",n);
                if ({ph,pv,pd,bypass_rgb} !== {hs,vs,de,rgb}) $fatal(1,"bypass cycle %0d",n);
                n=n+1;
            end else if (count != -1) $fatal(1,"Malformed vector");
        end
        $fclose(fd);
        $display("PASS: %0d cycles, WIDTH=%0d, six configurations",n,WIDTH);
        $finish;
    end
endmodule
