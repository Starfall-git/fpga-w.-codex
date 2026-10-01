`timescale 1ns/1ps
/* v1.2 / 6: Full-frame detection then next-frame adaptive crop classification.
 * v1.1 / 6: Whole-frame CDC ownership, inference scheduling and fail-closed result.
 * Two consecutive accepted classifications are required. Results expire in 0.5s.
 * Status: flags[0] enable,[1]busy,[2]valid,[3]model present,[4]stale.
 * Class IDs0..4 = fist/peace/palm/ok/like; FF = no valid gesture.
 */
module gesture_auto_pipeline #(
    parameter CLOCK_HZ=96000000,
    parameter THRESHOLD_FILE="src/cnn/rom/threshold.hex"
)(
    input wire clk,rst_n,enable_i,
    input wire pixel_clk,frame_i,valid_i,
    input wire [7:0] gray_i,
    output wire [7:0] flags_o,class_o,
    output reg [15:0] margin_o,frame_o,
    output wire [15:0] roi_x_o,roi_y_o,roi_side_o,
    output wire [31:0] cycles_o
);
    wire request,mail_detect;
    reg acknowledge,command_detect;
    reg [10:0] command_x,command_y;
    reg [3:0] command_block;
    reg have_roi;
    wire [15:0] roi_frame;
    wire [15:0] roi_addr;
    wire [7:0] roi_data;
    gesture_capture u_roi(.pixel_clk(pixel_clk),.pixel_rst_n(rst_n),.frame_i(frame_i),
        .valid_i(valid_i),.gray_i(gray_i),.enable_i(enable_i),.ack_i(acknowledge),
        .detect_i(command_detect),.roi_x_i(command_x),.roi_y_i(command_y),.block_i(command_block),
        .request_o(request),.detect_o(mail_detect),.frame_id_o(roi_frame),.read_clk(clk),
        .read_addr_i(roi_addr),.read_data_o(roi_data));
    (* async_reg="true" *)reg req_meta,req_sync;
    reg start,active,engine_detect;
    reg [1:0] release_wait;
    reg [15:0] pending_frame;
    wire busy,done;
    wire [95:0] scores;
    wire dv;wire [4:0] dx,dy;wire [2:0] dc;wire signed [15:0] value_out;
    gesture_shared_cnn u_cnn(.clk(clk),.rst_n(rst_n && enable_i),.start_i(start),.detect_i(engine_detect),
        .roi_addr_o(roi_addr),.roi_data_i(roi_data),.busy_o(busy),.done_o(done),
        .scores_o(scores),.cycles_o(cycles_o),.detect_valid_o(dv),.detect_x_o(dx),.detect_y_o(dy),
        .detect_channel_o(dc),.detect_value_o(value_out));
    wire box_valid;wire [10:0] box_x,box_y;wire [3:0] box_block;
    wire signed [15:0] box_score;
    gesture_box_decoder u_box(.clk(clk),.rst_n(rst_n && enable_i),.start_i(start && engine_detect),
        .valid_i(dv),.x_i(dx),.y_i(dy),.channel_i(dc),.value_i(value_out),
        .valid_o(box_valid),.roi_x_o(box_x),.roi_y_o(box_y),.block_o(box_block),.best_score_o(box_score));
    wire fresh;
    assign roi_x_o=have_roi && enable_i && fresh?{5'd0,command_x}:16'd0;
    assign roi_y_o=have_roi && enable_i && fresh?{5'd0,command_y}:16'd0;
    assign roi_side_o=have_roi && enable_i && fresh?{6'd0,command_block,6'd0}:16'd0;
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
    assign fresh=(age<CLOCK_HZ/2);
    wire result_valid=enable_i && fresh && repeats>=2 && confirmed<5;
    assign class_o=result_valid?confirmed:8'hff;
    assign flags_o={3'd0,!fresh,1'b1,result_valid,busy,enable_i};
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            req_meta<=0;req_sync<=0;acknowledge<=0;start<=0;active<=0;
            command_detect<=1;command_x<=0;command_y<=0;command_block<=8;have_roi<=0;
            engine_detect<=1;release_wait<=0;
            candidate<=8'hff;confirmed<=8'hff;repeats<=0;age<=CLOCK_HZ/2;
            margin_o<=0;frame_o<=0;pending_frame<=0;
        end else begin
            req_meta<=request;req_sync<=req_meta;start<=0;
            if(age<CLOCK_HZ/2)age<=age+1'b1;
            if(!enable_i)begin
                acknowledge<=req_sync;active<=0;repeats<=0;command_detect<=1;have_roi<=0;release_wait<=0;
                candidate<=8'hff;confirmed<=8'hff;age<=CLOCK_HZ/2;margin_o<=0;
            end else begin
                if(!active && !busy && release_wait==0 && req_sync!=acknowledge)begin
                    if(mail_detect==command_detect && (mail_detect || have_roi))begin
                        start<=1;active<=1;engine_detect<=mail_detect;pending_frame<=roi_frame;
                    end else acknowledge<=req_sync;
                end
                // Keep command fields stable for two system clocks before releasing mailbox.
                if(release_wait!=0)begin
                    release_wait<=release_wait-1'b1;
                    if(release_wait==1)begin acknowledge<=req_sync;active<=0;end
                end
                if(done && active)begin
                    if(engine_detect)begin
                        // Last head value is registered on done; process decoder one cycle later.
                        release_wait<=3;
                    end else begin
                    command_detect<=1;release_wait<=2;age<=0;frame_o<=pending_frame;
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
                if(release_wait==3)begin
                    age<=0;frame_o<=pending_frame;
                    if(box_valid)begin
                        command_detect<=0;command_x<=box_x;command_y<=box_y;command_block<=box_block;have_roi<=1;
                    end else begin
                        command_detect<=1;have_roi<=0;repeats<=0;candidate<=8'hff;confirmed<=8'hff;margin_o<=0;
                    end
                end
            end
        end
    end
endmodule
