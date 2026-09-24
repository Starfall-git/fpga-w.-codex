`timescale 1ns/1ps
/* V0.11 / 55: independent directional-kernel vectors, comparator limits,
   polarity, invalid windows and blanking. Controls settle for five clocks. */
module sobel8_tb;
    reg clk=0, rst=0, hs=1, vs=1, de=0, valid=0, polarity=1;
    reg [71:0] pixels=0;
    reg [11:0] threshold=0;
    wire [23:0] adaptive_rgb, fixed_rgb, magnitude_rgb;
    wire [2:0] h,v,d;
    always #5 clk=~clk;
    video_sobel #(.ADAPTIVE_THRESHOLD(1)) adaptive_dut
      (.clk(clk),.rst_n(rst),.BINARY_OUTPUT(polarity),.THRESHOLD(threshold),
       .pixels_i(pixels),.hs_i(hs),.vs_i(vs),.de_i(de),.window_valid_i(valid),
       .rgb_o(adaptive_rgb),.hs_o(h[0]),.vs_o(v[0]),.de_o(d[0]));
    video_sobel #(.ADAPTIVE_THRESHOLD(0)) fixed_dut
      (.clk(clk),.rst_n(rst),.BINARY_OUTPUT(polarity),.THRESHOLD(threshold),
       .pixels_i(pixels),.hs_i(hs),.vs_i(vs),.de_i(de),.window_valid_i(valid),
       .rgb_o(fixed_rgb),.hs_o(h[1]),.vs_o(v[1]),.de_o(d[1]));
    video_sobel #(.GRAYSCALE_OUTPUT(1)) magnitude_dut
      (.clk(clk),.rst_n(rst),.BINARY_OUTPUT(polarity),.THRESHOLD(threshold),
       .pixels_i(pixels),.hs_i(hs),.vs_i(vs),.de_i(de),.window_valid_i(valid),
       .rgb_o(magnitude_rgb),.hs_o(h[2]),.vs_o(v[2]),.de_o(d[2]));
    integer fd,n,count=0;
    reg [23:0] ea,ef,em;
    initial begin
        repeat(3) @(negedge clk); rst=1;
        fd=$fopen("vectors.txt","r"); if(!fd) $fatal(1,"vectors missing");
        while(!$feof(fd)) begin
            @(negedge clk);
            n=$fscanf(fd,"%h %h %h %h %h %h %h %h %h %h\n",
                pixels,threshold,polarity,de,valid,hs,vs,ea,ef,em);
            if(n==10) begin
                repeat(5) @(posedge clk); #1;
                if({adaptive_rgb,fixed_rgb,magnitude_rgb} !== {ea,ef,em})
                    $fatal(1,"vector %0d expected=%h actual=%h",count,
                        {ea,ef,em},{adaptive_rgb,fixed_rgb,magnitude_rgb});
                if(h !== {3{hs}} || v !== {3{vs}} || d !== {3{de}})
                    $fatal(1,"sync mismatch %0d",count);
                count=count+1;
            end else if(n!=-1) $fatal(1,"bad vector");
        end
        $display("PASS SOBEL8: %0d vectors",count); $finish;
    end
endmodule
