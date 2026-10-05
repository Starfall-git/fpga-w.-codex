`timescale 1ns/1ps
// One immutable 64x64 RAW8 snapshot. Camera never receives backpressure.
// Request/completion toggles transfer ownership of a dual-clock RAM bank.
// The CPU must finish reading before issuing the next request.
module cnn_gray_snapshot #(
    parameter ROI_X=384, ROI_Y=104
)(
    input wire cam_clk,cam_rst_n,frame_valid,pixel_valid,
    input wire [7:0] gray,
    input wire PCLK,PRESETn,
    input wire [15:0] PADDR,
    input wire PSEL,PENABLE,PWRITE,
    input wire [31:0] PWDATA,
    output wire PREADY,PSLVERROR,
    output reg [31:0] PRDATA
);
    wire reset_n=PRESETn && cam_rst_n;
    (* async_reg="true" *) reg [1:0] cam_run,cpu_run;
    always @(posedge cam_clk or negedge reset_n)
        if(!reset_n) cam_run<=0; else cam_run<={cam_run[0],1'b1};
    always @(posedge PCLK or negedge reset_n)
        if(!reset_n) cpu_run<=0; else cpu_run<={cpu_run[0],1'b1};
    reg request_toggle,done_toggle;
    (* async_reg="true" *) reg req_meta,req_sync,done_meta,done_sync;
    reg req_seen,done_seen,pending,capturing,prev_fv,prev_pv;
    reg [11:0] x,y;
    reg [12:0] count;
    reg [23:0] packed_low;
    reg [31:0] frame_counter,held_frame;
    reg held_error;
    reg [12:0] held_count;
    reg busy,ready,error;
    reg [31:0] completed_frame;
    reg [12:0] completed_count;
    reg [31:0] memory [0:1023];
    reg [31:0] read_word;
    // No reset on RAM: validity/ownership excludes uninitialized reads.
    always @(posedge PCLK) read_word<=memory[PADDR[11:2]];
    wire sample_pixel=capturing && frame_valid && pixel_valid &&
        x>=ROI_X && x<ROI_X+512 && y>=ROI_Y && y<ROI_Y+512 &&
        x[2:0]==((ROI_X+4)%8) && y[2:0]==((ROI_Y+4)%8);
    always @(posedge cam_clk) begin
        if(cam_run[1] && sample_pixel && count[1:0]==3)
            memory[count[11:2]]<={gray,packed_low};
    end
    always @(posedge cam_clk or negedge reset_n) begin
        if(!reset_n) begin
            req_meta<=0;req_sync<=0;req_seen<=0;pending<=0;capturing<=0;
            prev_fv<=0;prev_pv<=0;x<=0;y<=0;count<=0;packed_low<=0;
            frame_counter<=0;held_frame<=0;held_error<=0;held_count<=0;done_toggle<=0;
        end else if(!cam_run[1]) begin
            req_meta<=0;req_sync<=0;req_seen<=0;pending<=0;capturing<=0;
            prev_fv<=frame_valid;prev_pv<=pixel_valid;x<=0;y<=0;
        end else begin
            req_meta<=request_toggle;req_sync<=req_meta;
            prev_fv<=frame_valid;prev_pv<=pixel_valid;
            if(req_sync!=req_seen) begin req_seen<=req_sync;pending<=1;end
            if(!frame_valid) begin x<=0;y<=0;end
            else if(pixel_valid) x<=x+1'b1;
            else begin x<=0;if(prev_pv) y<=y+1'b1;end
            if(frame_valid && !prev_fv) begin
                frame_counter<=frame_counter+1'b1;
                if(pending) begin
                    pending<=0;capturing<=1;count<=0;
                    held_frame<=frame_counter+1'b1;held_error<=0;
                end
            end
            if(sample_pixel) begin
                case(count[1:0])
                    0: packed_low[7:0]<=gray;
                    1: packed_low[15:8]<=gray;
                    2: packed_low[23:16]<=gray;
                    3: begin end
                endcase
                count<=count+1'b1;
                if(count==4095) begin
                    capturing<=0;held_count<=4096;held_error<=0;done_toggle<=~done_toggle;
                end
            end
            // A truncated camera frame is a failed snapshot, never a valid image.
            if(capturing && prev_fv && !frame_valid) begin
                capturing<=0;held_count<=count;held_error<=1;done_toggle<=~done_toggle;
            end
        end
    end
    wire access=PSEL && PENABLE;
    wire data_address=PADDR[15:12]==4'h1 && PADDR[1:0]==0;
    wire command=PADDR==16'h0048;
    reg address_ok;
    always @* begin
        PRDATA=0;address_ok=1;
        if(data_address) PRDATA=read_word;
        else case(PADDR)
            16'h0040: PRDATA=32'h43415031; // CAP1
            16'h0044: PRDATA={29'd0,error,busy,ready};
            16'h0048: PRDATA=0; // write 1: capture next complete frame ROI
            16'h004c: PRDATA=completed_frame;
            16'h0050: PRDATA=(ROI_Y<<16)|ROI_X;
            16'h0054: PRDATA=((ROI_Y+512)<<16)|(ROI_X+512);
            16'h0058: PRDATA={19'd0,completed_count};
            default: address_ok=0;
        endcase
    end
    assign PREADY=1;
    assign PSLVERROR=access && (!cpu_run[1] || !address_ok ||
        (PWRITE && (!command || PWDATA!=1 || busy)) ||
        (!PWRITE && data_address && !ready));
    always @(posedge PCLK or negedge reset_n) begin
        if(!reset_n) begin
            request_toggle<=0;done_meta<=0;done_sync<=0;done_seen<=0;
            busy<=0;ready<=0;error<=0;completed_frame<=0;completed_count<=0;
        end else if(cpu_run[1]) begin
            done_meta<=done_toggle;done_sync<=done_meta;
            if(done_sync!=done_seen) begin
                done_seen<=done_sync;busy<=0;ready<=!held_error;error<=held_error;
                completed_frame<=held_frame;completed_count<=held_count;
            end
            if(access && PWRITE && !PSLVERROR && command) begin
                request_toggle<=~request_toggle;busy<=1;ready<=0;error<=0;completed_count<=0;
            end
        end
    end
endmodule
