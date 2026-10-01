`timescale 1ns/1ps
/* v1.1 / 4: Shared signed INT8 MAC, four stride-2 Conv/ReLU layers + FC6.
 * 64x64x1 -> 32x32x8 -> 16x16x16 -> 8x8x24 -> 4x4x32 -> six Q8 logits.
 * SAME padding is zero on top/left and one on bottom/right (even inputs).
 * ROM weights: output-channel, kernel-y, kernel-x, input-channel order.
 * One synchronous ROM/RAM read followed by one MAC. No CPU/DDR dependency.
 */
module gesture_cnn #(
    parameter WEIGHTS_FILE="src/cnn/rom/weights.hex",
    parameter BIASES_FILE="src/cnn/rom/biases.hex",
    parameter SHIFTS_FILE="src/cnn/rom/shifts.hex"
)(
    input wire clk,rst_n,start_i,
    output reg [11:0] roi_addr_o,
    input wire [7:0] roi_data_i,
    output wire busy_o,
    output reg done_o,
    output reg [95:0] scores_o,
    output reg [31:0] cycles_o
);
    reg signed [7:0] weights[0:14663];
    reg signed [31:0] biases[0:85];
    reg [7:0] shifts[0:4];
    reg signed [7:0] feature_a[0:8191],feature_b[0:8191];
    initial begin
        $readmemh(WEIGHTS_FILE,weights);
        $readmemh(BIASES_FILE,biases);
        $readmemh(SHIFTS_FILE,shifts);
    end
    localparam IDLE=0,LOAD_ADDR=1,LOAD_WAIT=2,LOAD_WRITE=3,
               BIAS_READ=4,BIAS_USE=5,READ_MAC=6,DO_MAC=7,STORE=8;
    reg [3:0] state;
    reg [2:0] layer;
    reg bank;
    reg [6:0] din,dout,cin,cout;
    reg [9:0] taps;
    reg [13:0] weight_base,weight_start,weight_addr;
    reg [6:0] bias_base;
    reg [13:0] output_total,output_index;
    reg [5:0] ox,oy,oc,ic;
    reg [1:0] kx,ky;
    reg [9:0] tap;
    reg signed [31:0] acc,bias_q;
    reg signed [7:0] act_q,weight_q;
    wire signed [15:0] product=act_q*weight_q;
    wire [6:0] ix={ox,1'b0}+kx,iy={oy,1'b0}+ky;
    wire padding=(ix>=din || iy>=din);
    // Dimensions are powers of two; channel count24 uses shift+add below.
    reg [12:0] spatial_addr,read_addr;
    always @* begin
        case(layer)
            0:spatial_addr=(iy<<6)+ix;
            1:spatial_addr=(iy<<5)+ix;
            2:spatial_addr=(iy<<4)+ix;
            default:spatial_addr=(iy<<3)+ix;
        endcase
        case(layer)
            0:read_addr=spatial_addr;
            1:read_addr=(spatial_addr<<3)+ic;
            2:read_addr=(spatial_addr<<4)+ic;
            3:read_addr=(spatial_addr<<4)+(spatial_addr<<3)+ic;
            default:read_addr=tap;
        endcase
    end
    wire signed [31:0] round_add=(shifts[layer]==0)?0:(32'sd1<<(shifts[layer]-1));
    wire signed [31:0] scaled=(acc+round_add)>>>shifts[layer];
    wire signed [15:0] logit=(scaled>32767)?16'sh7fff:((scaled< -32768)?16'sh8000:scaled[15:0]);
    wire [7:0] activated=(scaled<0)?8'd0:((scaled>127)?8'd127:scaled[7:0]);
    assign busy_o=(state!=IDLE);

    task configure_layer;
        input [2:0] number;
        begin
            layer<=number;ox<=0;oy<=0;oc<=0;output_index<=0;
            case(number)
                0:begin din<=64;dout<=32;cin<=1;cout<=8;taps<=9;
                        weight_base<=0;weight_start<=0;bias_base<=0;output_total<=8192;end
                1:begin din<=32;dout<=16;cin<=8;cout<=16;taps<=72;
                        weight_base<=72;weight_start<=72;bias_base<=8;output_total<=4096;end
                2:begin din<=16;dout<=8;cin<=16;cout<=24;taps<=144;
                        weight_base<=1224;weight_start<=1224;bias_base<=24;output_total<=1536;end
                3:begin din<=8;dout<=4;cin<=24;cout<=32;taps<=216;
                        weight_base<=4680;weight_start<=4680;bias_base<=48;output_total<=512;end
                default:begin din<=4;dout<=1;cin<=32;cout<=6;taps<=512;
                        weight_base<=11592;weight_start<=11592;bias_base<=80;output_total<=6;end
            endcase
        end
    endtask

    // RAM arrays have no reset, allowing block-RAM inference.
    always @(posedge clk) begin
        if(state==LOAD_WRITE) feature_a[roi_addr_o]<=roi_data_i^8'h80;
        if(state==READ_MAC) begin
            act_q <= (layer!=4 && padding)?8'sd0:(bank?feature_b[read_addr]:feature_a[read_addr]);
            weight_q<=weights[weight_addr];
        end
        if(state==BIAS_READ) bias_q<=biases[bias_base+oc];
        if(state==STORE && layer!=4) begin
            if(bank)feature_a[output_index]<=activated;
            else feature_b[output_index]<=activated;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;done_o<=0;scores_o<=0;cycles_o<=0;roi_addr_o<=0;
            layer<=0;bank<=0;din<=0;dout<=0;cin<=0;cout<=0;taps<=0;
            weight_base<=0;weight_start<=0;weight_addr<=0;bias_base<=0;
            output_total<=0;output_index<=0;ox<=0;oy<=0;oc<=0;ic<=0;kx<=0;ky<=0;tap<=0;acc<=0;
        end else begin
            done_o<=0;
            if(busy_o)cycles_o<=cycles_o+1'b1;
            case(state)
                IDLE:if(start_i)begin state<=LOAD_ADDR;roi_addr_o<=0;cycles_o<=0;scores_o<=0;bank<=0;end
                LOAD_ADDR:state<=LOAD_WAIT;
                LOAD_WAIT:state<=LOAD_WRITE;
                LOAD_WRITE:if(roi_addr_o==4095)begin configure_layer(0);state<=BIAS_READ;end
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
                    if(layer==4)scores_o[oc*16 +:16]<=logit;
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
