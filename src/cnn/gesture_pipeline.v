`timescale 1ns/1ps
/* v1.1 / 6: Whole-frame CDC ownership, inference scheduling and fail-closed result.
 * Two consecutive accepted classifications are required. Results expire in 0.5s.
 * Status: flags[0] enable,[1]busy,[2]valid,[3]model present,[4]stale.
 * Class IDs0..4 = fist/peace/palm/ok/like; FF = no valid gesture.
 */
module gesture_pipeline #(
    parameter CLOCK_HZ=96000000,
    parameter THRESHOLD_FILE="src/cnn/rom/threshold.hex"
)(
    input wire clk,rst_n,enable_i,
    input wire pixel_clk,frame_i,valid_i,
    input wire [7:0] gray_i,
    output wire [7:0] flags_o,class_o,
    output reg [15:0] margin_o,frame_o,
    output wire [31:0] cycles_o
);
    wire request;
    reg acknowledge;
    wire [15:0] roi_frame;
    wire [11:0] roi_addr;
    wire [7:0] roi_data;
    gesture_roi u_roi(.pixel_clk(pixel_clk),.pixel_rst_n(rst_n),.frame_i(frame_i),
        .valid_i(valid_i),.gray_i(gray_i),.enable_i(enable_i),.ack_i(acknowledge),
        .request_o(request),.frame_id_o(roi_frame),.read_clk(clk),
        .read_addr_i(roi_addr),.read_data_o(roi_data));
    (* async_reg="true" *)reg req_meta,req_sync;
    reg start,active;
    reg [15:0] pending_frame;
    wire busy,done;
    wire [95:0] scores;
    gesture_cnn u_cnn(.clk(clk),.rst_n(rst_n && enable_i),.start_i(start),
        .roi_addr_o(roi_addr),.roi_data_i(roi_data),.busy_o(busy),.done_o(done),
        .scores_o(scores),.cycles_o(cycles_o));
    reg [15:0] threshold[0:0];
    initial $readmemh(THRESHOLD_FILE,threshold);
    reg signed [15:0] best,second,value;
    reg [2:0] best_id;
    integer i;
    always @* begin
        best=-32768;second=-32768;best_id=0;value=0;
        for(i=0;i<6;i=i+1)begin
            value=$signed(scores[i*16 +:16]);
            if(value>best)begin second=best;best=value;best_id=i;end
            else if(value>second)second=value;
        end
    end
    wire [16:0] gap=$signed({best[15],best})-$signed({second[15],second});
    wire accepted=(best_id<5 && gap>=threshold[0]);
    reg [7:0] candidate,confirmed;
    reg [1:0] repeats;
    reg [31:0] age;
    wire fresh=(age<CLOCK_HZ/2);
    wire result_valid=enable_i && fresh && repeats>=2 && confirmed<5;
    assign class_o=result_valid?confirmed:8'hff;
    assign flags_o={3'd0,!fresh,1'b1,result_valid,busy,enable_i};
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            req_meta<=0;req_sync<=0;acknowledge<=0;start<=0;active<=0;
            candidate<=8'hff;confirmed<=8'hff;repeats<=0;age<=CLOCK_HZ/2;
            margin_o<=0;frame_o<=0;pending_frame<=0;
        end else begin
            req_meta<=request;req_sync<=req_meta;start<=0;
            if(age<CLOCK_HZ/2)age<=age+1'b1;
            if(!enable_i)begin
                acknowledge<=req_sync;active<=0;repeats<=0;
                candidate<=8'hff;confirmed<=8'hff;age<=CLOCK_HZ/2;margin_o<=0;
            end else begin
                if(!active && !busy && req_sync!=acknowledge)begin
                    start<=1;active<=1;pending_frame<=roi_frame;
                end
                if(done && active)begin
                    active<=0;acknowledge<=req_sync;age<=0;frame_o<=pending_frame;
                    margin_o<=gap[16]?16'hffff:gap[15:0];
                    if(accepted)begin
                        candidate<={5'd0,best_id};
                        if(fresh && candidate=={5'd0,best_id})begin
                            if(repeats<2)repeats<=repeats+1'b1;
                            confirmed<={5'd0,best_id};
                        end else begin repeats<=1;confirmed<=8'hff;end
                    end else begin repeats<=0;candidate<=8'hff;confirmed<=8'hff;end
                end
            end
        end
    end
endmodule
