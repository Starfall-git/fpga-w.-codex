`timescale 1ns/1ps
/* V0.7 / 34: independent wire-level sensor BFM + pixel reference checks.
   Delays scale with CLK_FREQ=100000; no ACK bypass or force of DUT internals. */
module ar0135_tb;
    reg clk=0; always #5 clk=~clk;
    reg rst=0;
    wire scl, sda_o, sda_oe, done, error;
    tri1 sda;
    reg slave_low=0;
    assign sda=sda_oe?sda_o:1'bz;
    assign sda=slave_low?1'b0:1'bz;
    wire [15:0] id;
    wire [7:0] index;
    ar0135_init #(.CLK_FREQ(100000),.I2C_FREQ(2500)) init_i
        (clk,rst,scl,sda_o,sda_oe,sda,done,error,id,index);
    wire absent_scl,absent_o,absent_oe,absent_done,absent_error;
    wire [15:0] absent_id; wire [7:0] absent_index;
    ar0135_init #(.CLK_FREQ(100000),.I2C_FREQ(2500)) absent_i
        (clk,rst,absent_scl,absent_o,absent_oe,1'b1,absent_done,absent_error,absent_id,absent_index);
    reg configured=0, fv=0,lv=0;
    reg [7:0] raw=0;
    wire frame_valid,pixel_valid; wire [15:0] rgb;
    localparam W=1280,H=720;
    ar0135_capture capture_i(clk,rst,configured,fv,lv,raw,frame_valid,pixel_valid,rgb);
    integer writes=0, attempts=0, seen=0, frames=0;
    reg injected=0;
    reg [15:0] regs[0:65535];
    reg [7:0] b0,b1,b2,b3,b4;
    reg [15:0] addr,value;
    time reset_stop=0, pll_stop=0, start_time;
    task start_bus;
        begin
            @(negedge sda);
            while(scl!==1) @(negedge sda);
        end
    endtask
    task receive_byte(output reg [7:0] b,input bit ack);
        integer j;
        begin
            for(j=7;j>=0;j=j-1) begin @(posedge scl); #1; b[j]=sda; end
            @(negedge scl); #1; slave_low=ack;
            @(posedge scl); @(negedge scl); #1; slave_low=0;
        end
    endtask
    task send_byte(input reg [7:0] b,input bit expected_ack);
        integer j;
        begin
            /* Enter on low SCL after address ACK or preceding RX ACK. */
            for(j=7;j>=0;j=j-1) begin
                slave_low=~b[j]; @(posedge scl); @(negedge scl); #1;
            end
            slave_low=0; @(posedge scl); #1;
            if(sda!==!expected_ack) $fatal(1,"Master RX ACK mismatch");
            @(negedge scl); #1;
        end
    endtask
    task stop_bus;
        begin @(posedge sda); while(scl!==1) @(posedge sda); end
    endtask
    initial begin : sensor
        wait(rst);
        forever begin
            start_bus(); start_time=$time;
            receive_byte(b0,1); if(b0!=8'h20) $fatal(1,"Bad sensor address %h",b0);
            receive_byte(b1,1); receive_byte(b2,1); addr={b1,b2};
            if(addr==16'h3000) begin
                start_bus();
                receive_byte(b0,1); if(b0!=8'h21) $fatal(1,"Bad read address");
                send_byte(8'h05,1); send_byte(8'h54,0); stop_bus();
            end else begin
                /* NACK data high byte once: index must stay and full write retry. */
                if(addr==16'h302C && !injected) begin
                    receive_byte(b3,0); injected=1; attempts=attempts+1;
                    stop_bus();
                end else begin
                    receive_byte(b3,1); receive_byte(b4,1); value={b3,b4}; stop_bus();
                    if(addr==0) $fatal(1,"Delay sentinel was sent over I2C");
                    if(addr==16'h301A && value==16'h10D8 && start_time-reset_stop<10000)
                        $fatal(1,"Software reset delay too short");
                    if(addr==16'h3002 && start_time-pll_stop<2000)
                        $fatal(1,"PLL delay too short");
                    if(addr==16'h301A && value==16'h10D9) reset_stop=$time;
                    if(addr==16'h30B0) pll_stop=$time;
                    regs[addr]=value; writes=writes+1;
                end
            end
        end
    end
    task tick(input bit f,input bit l,input reg[7:0] d);
        begin @(negedge clk);fv=f;lv=l;raw=d; @(posedge clk); #1; end
    endtask
    reg checking=0;
    integer row,col,p;
    reg [7:0] expected_gray;
    always @(negedge clk) if(checking && pixel_valid) begin
        expected_gray=((seen%W)+3*((seen/W)%H))%256;
        if(rgb!=={expected_gray[7:3],expected_gray[7:2],expected_gray[7:3]})
            $fatal(1,"Pixel %0d RGB mismatch: got%h gray%h",seen,rgb,expected_gray);
        if(!frame_valid) $fatal(1,"Pixel outside frame");
        seen=seen+1;
    end
    initial begin
        repeat(4) @(negedge clk); rst=1;
        /* Configuration becomes ready in mid-frame: discard that partial frame. */
        tick(1,0,0); configured=1;
        repeat(20) begin tick(1,1,8'hfe); if(pixel_valid) $fatal(1,"Partial first frame captured"); end
        tick(0,0,0); repeat(4) tick(0,0,0);
        checking=1;
        for(p=0;p<2;p=p+1) begin
            repeat(6) tick(1,0,0);
            for(row=0;row<H+4;row=row+1) begin
                for(col=0;col<W;col=col+1)
                    tick(1,1,(row<2 || row>=H+2)?8'hee:((col+3*(row-2))%256));
                repeat(5) tick(1,0,0);
            end
            repeat(6) tick(1,0,0); repeat(10) tick(0,0,0);
            if(seen!=(p+1)*W*H) $fatal(1,"Frame size mismatch %0d",seen);
        end
        wait(done || error);
        if(error || id!=16'h0554 || index!=27 || writes!=23 || !injected || attempts!=1)
            $fatal(1,"Init mismatch done%0d error%0d id%h index%0d writes%0d",done,error,id,index,writes);
        if(!absent_error || absent_done) $fatal(1,"Missing camera falsely configured");
        if(regs['h3008]-regs['h3004]+1!=W || regs['h3006]-regs['h3002]+1!=H)
            $fatal(1,"Window mismatch");
        if(regs['h3064]!=16'h1982 || regs['h3100]!=16'h13 || regs['h301A]!=16'h10DC ||
           /* V0.10 / 47: sensor vertical readout corrects board orientation. */
           regs['h3040]!=16'h8000 || regs['h3028]!=16'h10 || regs['h3030]!=44)
            $fatal(1,"Mode/PLL/AE mismatch");
        $display("PASS AR0135: ACK/retry/missing-device/ID/delays/ROI/AE, 2 full720p frames (%0d pixels)",seen);
        $finish;
    end
    initial begin #30000000; $fatal(1,"Timeout"); end
endmodule
