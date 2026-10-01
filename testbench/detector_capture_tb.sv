`timescale 1ns/1ps
// v1.2 / 8: Exhaustive pixel comparison at full frame, corners and variable scales.
module detector_capture_tb;
    reg pc=0,sc=0,rst=0,fv=0,pv=0,en=0,ack=0,mode=1;
    always #7 pc=~pc;always #5 sc=~sc;
    reg [10:0] rx=0,ry=0;reg[3:0]block=10;reg[7:0]gray=0;
    reg [15:0]addr=0;wire[7:0]data;wire req,kind;wire[15:0]fid;
    integer x,y,u,v,a,b,total,expected,checked=0,offset=0,test;
    reg old_req;
    gesture_capture dut(.pixel_clk(pc),.pixel_rst_n(rst),.frame_i(fv),.valid_i(pv),.gray_i(gray),
        .enable_i(en),.ack_i(ack),.detect_i(mode),.roi_x_i(rx),.roi_y_i(ry),.block_i(block),
        .request_o(req),.detect_o(kind),.frame_id_o(fid),.read_clk(sc),.read_addr_i(addr),.read_data_o(data));
    task send_frame;
        begin
            @(negedge pc);fv=1;repeat(8)@(negedge pc);
            for(y=0;y<720;y=y+1)begin
                for(x=0;x<1280;x=x+1)begin pv=1;gray=(x*3+y*5+offset)&255;@(negedge pc);end
                pv=0;repeat(3)@(negedge pc);
            end
            fv=0;repeat(8)@(negedge pc);
        end
    endtask
    task verify;
        input integer width,height,s,left,top;
        begin
            for(v=0;v<height;v=v+1)for(u=0;u<width;u=u+1)begin
                total=0;
                for(b=0;b<s;b=b+1)for(a=0;a<s;a=a+1)
                    total=total+(((left+u*s+a)*3+(top+v*s+b)*5+offset)&255);
                expected=(total+(s*s)/2)/(s*s);
                @(negedge sc);addr=v*width+u;repeat(2)@(negedge sc);
                if(data!==expected[7:0])$fatal(1,"Capture test%0d xy%0d,%0d got%0d expected%0d",test,u,v,data,expected);
                checked=checked+1;
            end
        end
    endtask
    initial begin
        repeat(8)@(negedge pc);rst=1;en=1;repeat(8)@(negedge pc);
        for(test=0;test<7;test=test+1)begin
            mode=(test==0);
            case(test)
                0:begin rx=0;ry=0;block=10;end
                1:begin rx=0;ry=0;block=1;end
                2:begin rx=1216;ry=0;block=1;end
                3:begin rx=0;ry=656;block=1;end
                4:begin rx=1216;ry=656;block=1;end
                5:begin rx=576;ry=16;block=11;end
                6:begin rx=333;ry=197;block=5;end
            endcase
            offset=test*17;old_req=req;ack=req;repeat(8)@(negedge pc);send_frame();
            if(req==old_req || kind!==mode)$fatal(1,"Mailbox/mode missing");
            if(mode)verify(256,144,5,0,0);else verify(64,64,block,rx,ry);
        end
        old_req=req;send_frame();if(req!==old_req)$fatal(1,"Overwrote owned frame");
        en=0;ack=req;repeat(8)@(negedge pc);send_frame();if(req!==old_req)$fatal(1,"Disabled frame published");
        $display("PASS DETECTOR CAPTURE: %0d exact averages, full frame/corners/scales/ownership/disable",checked);$finish;
    end
    initial begin #250000000;$fatal(1,"capture timeout");end
endmodule
