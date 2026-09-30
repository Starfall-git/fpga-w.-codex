`timescale 1ns/1ps
/* V0.5: independent byte-addressed AXI memory, random stalls and Python pixel oracle. */
module compare_reader_tb;
    parameter WIDTH=1280, HEIGHT=720, STRESS=1;
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
    reg [3:0] frame_index=0;
    reg [11:0] selection=0;
    axi_transform_reader #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.FRAME_BITS(4),.COMPARE_ENABLE(1)) dut(
        .compare_i(1'b1),.compare_mask_i(selection),.axi_clk(clk),.axi_reset(reset),.frame_index_i(frame_index),.frame_switch_o(frame_switch),
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
                if(!selection[addr[25:22]] || (addr & 32'h3fffff)+(len+1)*16>WIDTH*HEIGHT*2)
                    $fatal(1,"Read outside frame");
                memory_addr=addr; remaining=len+1; active<=1; ar<=0; bursts=bursts+1;
            end
            if(rv && rr) begin rv<=0; if(rl) active<=0; end
            if(active && (!rv || rr) && remaining>0 && !bus_stall && (STRESS ? cycle%16<8 : cycle%5!=0)) begin
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
    integer n,x,y,columns,rows,cw,ch,iw,ih,ox,oy,col,row,id,index,expected,checked=0;
    integer ids[0:7];
    initial begin
      ids[0]=1;ids[1]=3;ids[2]=4;ids[3]=5;ids[4]=7;ids[5]=8;ids[6]=10;ids[7]=11;
      geometry={16'd1,16'd1,16'(HEIGHT),16'(WIDTH),16'd0,16'd0,2'd0};
      #101;reset=0;
      for(n=1;n<=8;n=n+1) begin
        selection[ids[n-1]]=1;
        columns=n<=1 ? 1 : n<=4 ? 2 : 3;
        rows=(n+columns-1)/columns;cw=WIDTH/columns;ch=HEIGHT/rows;
        if(cw*HEIGHT<=ch*WIDTH) begin iw=cw;ih=cw*HEIGHT/WIDTH;end
        else begin ih=ch;iw=ch*WIDTH/HEIGHT;end
        ox=(cw-iw)/2;oy=(ch-ih)/2;
        blank_frame();
        for(y=0;y<HEIGHT;y=y+1) begin
          for(x=0;x<WIDTH;x=x+1) begin
            col=x/cw;row=y/ch;index=row*columns+col;
            expected=0;
            if(col<columns && row<rows && index<n && x%cw>=ox && x%cw<ox+iw && y%ch>=oy && y%ch<oy+ih) begin
              sx=(x%cw-ox)*WIDTH/iw;sy=(y%ch-oy)*HEIGHT/ih;
              expected=source_pixel(sx,sy,ids[index]);
            end
            @(negedge pixel_clk);request=1;@(posedge pixel_clk);#1;
            if(pixel!==expected[15:0]) $fatal(1,"compare N%0d x%0d y%0d expected %h got %h state%0d",n,x,y,expected[15:0],pixel,dut.state);
            checked=checked+1;
          end
          @(negedge pixel_clk);request=0;
          repeat(370) @(negedge pixel_clk);
        end
        if(faults!==0) $fatal(1,"compare underflow/errors %b N%0d",faults,n);
        $display("PASS COMPARE N=%0d at 720p line deadline",n);
      end
      $display("PASS COMPARE all pixels=%0d",checked);$finish;
    end
    initial begin #500000000;$fatal(1,"compare timeout");end
endmodule

