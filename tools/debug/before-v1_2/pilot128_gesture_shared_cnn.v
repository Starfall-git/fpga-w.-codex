`timescale 1ns/1ps
/* v1.2 / 3: Reuse one MAC and RAM pair for full-frame detection and classification.
 * Classifier math remains v1.1. Detector: 128x72 ->64x36x8 ->32x18x16
 * ->16x9x24 ->16x9x32 (dilated3x3/s1,d2) ->16x9x5 (1x1 head).
 * Concatenated ROMs keep classifier at offset0, detector weights14664/bias86.
 */
module gesture_shared_cnn #(
    parameter WEIGHTS_FILE="src/cnn/rom_v1_2/weights.hex",
    parameter BIASES_FILE="src/cnn/rom_v1_2/biases.hex",
    parameter SHIFTS_FILE="src/cnn/rom_v1_2/shifts.hex"
)(
    input wire clk,rst_n,start_i,detect_i,
    output reg [13:0] roi_addr_o,
    output reg detect_valid_o,
    output reg [3:0] detect_x_o,detect_y_o,
    output reg [2:0] detect_channel_o,
    output reg signed [15:0] detect_value_o,
    input wire [7:0] roi_data_i,
    output wire busy_o,
    output reg done_o,
    output reg [95:0] scores_o,
    output reg [31:0] cycles_o
);
    reg signed [7:0] weights[0:26415];
    reg signed [31:0] biases[0:170];
    reg [7:0] shifts[0:13];
    reg signed [7:0] feature_a[0:18431],feature_b[0:18431];
    initial begin
        $readmemh(WEIGHTS_FILE,weights);
        $readmemh(BIASES_FILE,biases);
        $readmemh(SHIFTS_FILE,shifts);
    end
    localparam IDLE=0,LOAD_ADDR=1,LOAD_WAIT=2,LOAD_WRITE=3,
               BIAS_READ=4,BIAS_USE=5,READ_MAC=6,DO_MAC=7,STORE=8;
    reg [3:0] state;
    reg [2:0] layer;
    reg bank,detect;
    reg [7:0] din,dinh,dout,cin,cout;
    reg [9:0] taps;
    reg [14:0] weight_base,weight_start,weight_addr;
    reg [7:0] bias_base;
    reg [14:0] output_total,output_index;
    reg [6:0] ox,oy;
    reg [5:0] oc,ic;
    reg [1:0] kx,ky;
    reg [9:0] tap;
    reg signed [31:0] acc,bias_q;
    // v1.1 / 23: Dedicated synchronous read registers infer block RAM.
    reg signed [7:0] feature_a_q,feature_b_q,weight_q;
    reg padding_q;
    wire signed [7:0] act_q=padding_q?8'sd0:(bank?feature_b_q:feature_a_q);
    wire signed [15:0] product=act_q*weight_q;
    wire [8:0] ix=detect && layer==3?({2'b0,ox}+{6'b0,kx,1'b0}-9'd2):
                       (detect && layer==4?{2'b0,ox}:({1'b0,ox,1'b0}+kx));
    wire [8:0] iy=detect && layer==3?({2'b0,oy}+{6'b0,ky,1'b0}-9'd2):
                       (detect && layer==4?{2'b0,oy}:({1'b0,oy,1'b0}+ky));
    wire padding=(ix>=din || iy>=dinh);
    reg [14:0] spatial_addr,read_addr;
    always @* begin
        case(layer)
            0:spatial_addr=detect?(iy<<7)+ix:(iy<<6)+ix;
            1:spatial_addr=detect?(iy<<6)+ix:(iy<<5)+ix;
            2:spatial_addr=detect?(iy<<5)+ix:(iy<<4)+ix;
            default:spatial_addr=detect?(iy<<4)+ix:(iy<<3)+ix;
        endcase
        case(layer)
            0:read_addr=spatial_addr;
            1:read_addr=(spatial_addr<<3)+ic;
            2:read_addr=(spatial_addr<<4)+ic;
            3:read_addr=(spatial_addr<<4)+(spatial_addr<<3)+ic;
            default:read_addr=detect?(spatial_addr<<5)+ic:tap;
        endcase
    end
    // v1.2 / 13: separate output-channel scales preserve small box regressions.
    wire [3:0] shift_index=detect?(layer==4?4'd9+oc[2:0]:{1'b0,layer}+4'd5):{1'b0,layer};
    wire signed [31:0] round_add=(shifts[shift_index]==0)?0:(32'sd1<<(shifts[shift_index]-1));
    wire signed [31:0] scaled=(acc+round_add)>>>shifts[shift_index];
    wire signed [15:0] logit=(scaled>32767)?16'sh7fff:((scaled< -32768)?16'sh8000:scaled[15:0]);
    wire [7:0] activated=(scaled<0)?8'd0:((scaled>127)?8'd127:scaled[7:0]);
    assign busy_o=(state!=IDLE);

    task configure_layer;
        input [2:0] number;
        begin
            layer<=number;ox<=0;oy<=0;oc<=0;output_index<=0;
            if(detect)begin
                case(number)
                    0:begin din<=128;dinh<=72;dout<=64;cin<=1;cout<=8;taps<=9;
                        weight_base<=14664;weight_start<=14664;bias_base<=86;output_total<=18432;end
                    1:begin din<=64;dinh<=36;dout<=32;cin<=8;cout<=16;taps<=72;
                        weight_base<=14736;weight_start<=14736;bias_base<=94;output_total<=9216;end
                    2:begin din<=32;dinh<=18;dout<=16;cin<=16;cout<=24;taps<=144;
                        weight_base<=15888;weight_start<=15888;bias_base<=110;output_total<=3456;end
                    3:begin din<=16;dinh<=9;dout<=16;cin<=24;cout<=32;taps<=216;
                        weight_base<=19344;weight_start<=19344;bias_base<=134;output_total<=4608;end
                    default:begin din<=16;dinh<=9;dout<=16;cin<=32;cout<=5;taps<=32;
                        weight_base<=26256;weight_start<=26256;bias_base<=166;output_total<=720;end
                endcase
            end else case(number)
                0:begin din<=64;dinh<=64;dout<=32;cin<=1;cout<=8;taps<=9;
                        weight_base<=0;weight_start<=0;bias_base<=0;output_total<=8192;end
                1:begin din<=32;dinh<=32;dout<=16;cin<=8;cout<=16;taps<=72;
                        weight_base<=72;weight_start<=72;bias_base<=8;output_total<=4096;end
                2:begin din<=16;dinh<=16;dout<=8;cin<=16;cout<=24;taps<=144;
                        weight_base<=1224;weight_start<=1224;bias_base<=24;output_total<=1536;end
                3:begin din<=8;dinh<=8;dout<=4;cin<=24;cout<=32;taps<=216;
                        weight_base<=4680;weight_start<=4680;bias_base<=48;output_total<=512;end
                default:begin din<=4;dinh<=4;dout<=1;cin<=32;cout<=6;taps<=512;
                        weight_base<=11592;weight_start<=11592;bias_base<=80;output_total<=6;end
            endcase
        end
    endtask

    // RAM arrays have no reset, allowing block-RAM inference.
    always @(posedge clk) begin
        if(state==LOAD_WRITE || (state==STORE && layer!=4 && bank))
            feature_a[state==LOAD_WRITE?{1'b0,roi_addr_o}:output_index]
                <=state==LOAD_WRITE?(roi_data_i^8'h80):activated;
        if(state==STORE && layer!=4 && !bank)
            feature_b[output_index]<=activated;
        if(state==READ_MAC) begin
            feature_a_q<=feature_a[read_addr];
            feature_b_q<=feature_b[read_addr];
            padding_q<=((detect || layer!=4) && padding);
            weight_q<=weights[weight_addr];
        end
        if(state==BIAS_READ) bias_q<=biases[bias_base+oc];
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;done_o<=0;detect<=0;detect_valid_o<=0;detect_x_o<=0;detect_y_o<=0;detect_channel_o<=0;detect_value_o<=0;scores_o<=0;cycles_o<=0;roi_addr_o<=0;
            layer<=0;bank<=0;din<=0;dinh<=0;dout<=0;cin<=0;cout<=0;taps<=0;
            weight_base<=0;weight_start<=0;weight_addr<=0;bias_base<=0;
            output_total<=0;output_index<=0;ox<=0;oy<=0;oc<=0;ic<=0;kx<=0;ky<=0;tap<=0;acc<=0;
        end else begin
            done_o<=0;detect_valid_o<=0;
            if(busy_o)cycles_o<=cycles_o+1'b1;
            case(state)
                IDLE:if(start_i)begin state<=LOAD_ADDR;detect<=detect_i;roi_addr_o<=0;cycles_o<=0;scores_o<=0;bank<=0;end
                LOAD_ADDR:state<=LOAD_WAIT;
                LOAD_WAIT:state<=LOAD_WRITE;
                LOAD_WRITE:if(roi_addr_o==(detect?9215:4095))begin configure_layer(0);state<=BIAS_READ;end
                           else begin roi_addr_o<=roi_addr_o+1'b1;state<=LOAD_ADDR;end
                BIAS_READ:state<=BIAS_USE;
                BIAS_USE:begin
                    acc<=bias_q;tap<=0;ic<=0;kx<=0;ky<=0;
                    weight_addr<=weight_start;state<=READ_MAC;
                end
                READ_MAC:state<=DO_MAC;
                DO_MAC:begin
                    acc<=acc+{{16{product[15]}},product};
                    if(tap==taps-1)state<=STORE;
                    else begin
                        tap<=tap+1'b1;weight_addr<=weight_addr+1'b1;state<=READ_MAC;
                        if(ic==cin-1)begin ic<=0;if(kx==2)begin kx<=0;ky<=ky+1'b1;end else kx<=kx+1'b1;end
                        else ic<=ic+1'b1;
                    end
                end
                STORE:begin
                    if(layer==4)begin
                        if(detect)begin
                            detect_valid_o<=1;detect_x_o<=ox[3:0];detect_y_o<=oy[3:0];
                            detect_channel_o<=oc[2:0];detect_value_o<=logit;
                        end else scores_o[oc*16 +:16]<=logit;
                    end
                    if(output_index==output_total-1)begin
                        if(layer==4)begin done_o<=1;state<=IDLE;end
                        else begin configure_layer(layer+1'b1);bank<=~bank;state<=BIAS_READ;end
                    end else begin
                        output_index<=output_index+1'b1;state<=BIAS_READ;
                        if(oc==cout-1)begin
                            oc<=0;weight_start<=weight_base;
                            if(ox==dout-1)begin ox<=0;oy<=oy+1'b1;end else ox<=ox+1'b1;
                        end else begin oc<=oc+1'b1;weight_start<=weight_start+taps;end
                    end
                end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
