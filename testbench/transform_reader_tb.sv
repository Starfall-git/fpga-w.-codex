`timescale 1ns/1ps
/* V0.5: independent byte-addressed AXI memory, random stalls and Python pixel oracle. */
module transform_reader_tb;
    parameter WIDTH=32, HEIGHT=16;
    reg clk=0, pixel_clk=0, reset=1;
    /* Actual board AXI UI is clk_sys=96MHz; HDMI pixel clock is 74.4MHz. */
    always #5.208333 clk=~clk;
    always #6.720430 pixel_clk=~pixel_clk;
    wire [31:0] addr;
    wire [7:0] len;
    wire av, rr, frame_switch, cfg_ack;
    reg ar=0, rv=0, rl=0;
    reg [127:0] data=0;
    reg [1:0] resp=0;
    reg vs=1, request=0;
    reg [97:0] geometry;
    reg cfg_toggle=0;
    wire [15:0] pixel;
    wire [1:0] faults;
    reg [1:0] frame_index=0;
    axi_transform_reader #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) dut(
        .axi_clk(clk),.axi_reset(reset),.frame_index_i(frame_index),.frame_switch_o(frame_switch),
        .araddr_o(addr),.arlen_o(len),.arvalid_o(av),.arready_i(ar),
        .rdata_i(data),.rresp_i(resp),.rlast_i(rl),.rvalid_i(rv),.rready_o(rr),
        .pixel_clk(pixel_clk),.vs_i(vs),.request_i(request),.pixel_o(pixel),
        .geometry_i(geometry),.geometry_toggle_i(cfg_toggle),.geometry_ack_o(cfg_ack),.faults_o(faults));

    integer cycle=0, remaining=0, memory_addr=0, beat, lane, linear, sx, sy;
    integer bursts=0, switches=0;
    reg active=0, bus_stall=0, inject_error=0;
    reg held_ar=0;
    reg [31:0] old_addr;
    reg [7:0] old_len;
    function [15:0] source_pixel(input integer x,y,bank);
        source_pixel=((y*WIDTH+x)*37) ^ (bank*16'h4321) ^ (y*257);
    endfunction
    always @(posedge clk) begin
        if(reset) begin rv<=0; active<=0; ar<=0; held_ar<=0; cycle<=0; end
        else begin
            cycle<=cycle+1;
            ar<=!bus_stall && !active && !rv && cycle%7!=0;
            if(frame_switch) begin
                switches=switches+1;
                if(active || rv || av) $fatal(1,"Frame switched with outstanding AXI");
                // Emulate parent frame scheduler: new index arrives one clock after switch.
                frame_index<=frame_index==1 ? 2 : 1;
            end
            if(held_ar && (!av || addr!==old_addr || len!==old_len)) $fatal(1,"AR changed under backpressure");
            held_ar<=av && !ar; old_addr<=addr; old_len<=len;
            if(av && ar) begin
                if(active || rv) $fatal(1,"More than one outstanding burst");
                if(addr[3:0]!=0 || addr[11:0]+(len+1)*16>4096 || len>=128) $fatal(1,"AXI alignment/4KB/length");
                if(addr[31:22]!=frame_index || (addr & 32'h3fffff)+(len+1)*16>WIDTH*HEIGHT*2)
                    $fatal(1,"Read outside frame");
                memory_addr=addr; remaining=len+1; active<=1; ar<=0; bursts=bursts+1;
            end
            if(rv && rr) begin rv<=0; if(rl) active<=0; end
            if(active && (!rv || rr) && remaining>0 && !bus_stall && cycle%5!=0) begin
                for(lane=0;lane<8;lane=lane+1) begin
                    linear=((memory_addr & 32'h3fffff)/2)+lane;
                    data[127-lane*16 -: 16]<=source_pixel(linear%WIDTH,linear/WIDTH,memory_addr>>22);
                end
                rv<=1; rl<=remaining==1; resp<=inject_error ? 2'b10 : 0;
                memory_addr=memory_addr+16; remaining=remaining-1;
            end
        end
    end
    task blank_frame;
        begin
            @(negedge pixel_clk); vs=0; request=0;
            // Allow row prefetch; still shorter than real 720p vertical blank (30 lines).
            repeat(600+2*WIDTH) @(negedge pixel_clk);
            vs=1;
            repeat(30) @(negedge pixel_clk);
        end
    endtask
    integer f, cases, n, x,y, flags,cx,cy,cw,ch,zn,zd,expected,scan;
    integer checked=0;
    reg [1023:0] file_name;
    initial begin
        if(!$value$plusargs("VECTORS=%s",file_name)) $fatal(1,"Missing vectors");
        f=$fopen(file_name,"r"); scan=$fscanf(f,"%d",cases);
        geometry={16'd1,16'd1,16'(HEIGHT),16'(WIDTH),16'd0,16'd0,2'd0};
        #101; reset=0;
        for(n=0;n<cases;n=n+1) begin
            scan=$fscanf(f,"%d %d %d %d %d %d %d",flags,cx,cy,cw,ch,zn,zd);
            geometry={16'(zd),16'(zn),16'(ch),16'(cw),16'(cy),16'(cx),2'(flags)};
            cfg_toggle=~cfg_toggle;
            repeat(20) @(negedge pixel_clk);
            if(cfg_ack==cfg_toggle) $fatal(1,"Geometry changed outside frame boundary");
            blank_frame();
            if(cfg_ack!==cfg_toggle) $fatal(1,"Frame configuration not acknowledged");
            for(y=0;y<HEIGHT;y=y+1) begin
                for(x=0;x<WIDTH;x=x+1) begin
                    @(negedge pixel_clk); request=1;
                    scan=$fscanf(f,"%h",expected);
                    @(posedge pixel_clk); #1;
                    if(pixel!==expected[15:0]) $fatal(1,"case%0d x%0d y%0d expected%h got%h flags%0d crop%0d,%0d,%0d,%0d zoom%0d/%0d",
                        n,x,y,expected[15:0],pixel,flags,cx,cy,cw,ch,zn,zd);
                    checked=checked+1;
                end
                @(negedge pixel_clk); request=0;
                repeat(WIDTH==1280 ? 370 : 100+WIDTH/4) @(negedge pixel_clk);
            end
            if(faults!==0) $fatal(1,"Unexpected reader fault %b",faults);
        end
        // Bus stall across a frame boundary: keep AR stable, drain before switching,
        // and display an entire missing line as black, never stale pixels.
        bus_stall=1; blank_frame();
        for(x=0;x<WIDTH;x=x+1) begin
            @(negedge pixel_clk); request=1; @(posedge pixel_clk); #1;
            if(pixel!==0) $fatal(1,"Underflow exposed stale pixels");
        end
        @(negedge pixel_clk); request=0; vs=0;
        repeat(100) @(negedge pixel_clk);
        bus_stall=0;
        repeat(2000+WIDTH) @(negedge pixel_clk);
        vs=1;
        if(!faults[0]) $fatal(1,"Underflow not reported");
        inject_error=1; blank_frame();
        repeat(1000+WIDTH) @(negedge pixel_clk);
        if(!faults[1]) $fatal(1,"AXI error not reported");
        $display("PASS TRANSFORM: %0d cases, %0d pixels, %0d bursts, %0d frames, faults/drain/backpressure",cases,checked,bursts,switches);
        $finish;
    end
    initial begin #100000000; $fatal(1,"Transform test timeout"); end
endmodule
