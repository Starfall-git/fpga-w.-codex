/* V0.7 / 32: VIP AR0135 header DOUT[11:4] -> cmos_data[7:0].
 * One RAW8 sample per PCLK becomes one RGB565 gray pixel, keeping the existing
 * DDR/geometry/Sobel/HDMI contract. AE needs embedded data and statistics:
 * discard two leading metadata rows and all rows after the 720 image rows.
 * Configuration is synchronized; wait for a complete new FV before capture.
 */
module ar0135_capture #(
    parameter WIDTH=1280, HEIGHT=720, EMBEDDED_ROWS=2
) (
    input wire pclk, input wire rst_n, input wire configured,
    input wire fv, input wire lv, input wire [7:0] raw,
    output reg frame_valid, output reg pixel_valid, output reg [15:0] rgb565
);
    reg [1:0] reset_sync, config_sync;
    reg armed, active, fv_d, lv_d;
    reg [15:0] x, y;
    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin reset_sync<=0; config_sync<=0; end
        else begin reset_sync<={reset_sync[0],1'b1}; config_sync<={config_sync[0],configured}; end
    end
    always @(posedge pclk or negedge rst_n) begin
        if(!rst_n) begin
            armed<=0; active<=0; fv_d<=0; lv_d<=0; x<=0; y<=0;
            frame_valid<=0; pixel_valid<=0; rgb565<=0;
        end else if (!reset_sync[1] || !config_sync[1]) begin
            armed<=0; active<=0; fv_d<=fv; lv_d<=lv; x<=0; y<=0;
            frame_valid<=0; pixel_valid<=0; rgb565<=0;
        end else begin
            fv_d<=fv; lv_d<=lv;
            if(!fv) begin armed<=1; active<=0; x<=0; y<=0; end
            else begin
                if(!fv_d && armed) active<=1;
                if(lv) begin if(x!=16'hffff) x<=x+1'b1; end
                else begin
                    x<=0;
                    if(lv_d && y!=16'hffff) y<=y+1'b1;
                end
            end
            frame_valid<=active && fv;
            pixel_valid<=active && fv && lv && x<WIDTH &&
                         y>=EMBEDDED_ROWS && y<EMBEDDED_ROWS+HEIGHT;
            rgb565<={raw[7:3],raw[7:2],raw[7:3]};
        end
    end
endmodule
