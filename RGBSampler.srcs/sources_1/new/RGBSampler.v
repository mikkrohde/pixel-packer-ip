`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 
// Create Date: 21.12.2025 21:43:12
// Design Name: 
// Module Name: RGBSampler
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: Video sampler that captures RGB signals synchronized with 
//              HSYNC/VSYNC and writes to VideoBuffer
// 
// Dependencies: VideoBuffer
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module rgb_sampler #(
    parameter MAX_R_WIDTH      = 8,         // Maximum red channel width (8-bit standard)
    parameter MAX_G_WIDTH      = 8,         // Maximum green channel width
    parameter MAX_B_WIDTH      = 8,         // Maximum blue channel width
    parameter MAX_WIDTH        = 1920,      // Maximum horizontal resolution
    parameter MAX_HEIGHT       = 1080,      // Maximum vertical resolution
    parameter PIXEL_WIDTH      = 24,         // Total pixel width (R+G+B)
    parameter MAX_CHANNEL_WIDTH = 8
)(
    // System clock and reset
    input wire                      clk,
    input wire                      rst_n,
    
    // VGA input signals
    input wire [MAX_R_WIDTH-1:0]    vga_r,
    input wire [MAX_G_WIDTH-1:0]    vga_g,
    input wire [MAX_B_WIDTH-1:0]    vga_b,
    input wire                      vga_hsync,
    input wire                      vga_vsync,
    
    // Configuration
    input wire [15:0]               cfg_width,       // Active pixels per line
    input wire [15:0]               cfg_height,      // Active lines per frame
    input wire [3:0]                cfg_r_width,     // Actual R channel width (1-8)
    input wire [3:0]                cfg_g_width,     // Actual G channel width (1-8)
    input wire [3:0]                cfg_b_width,     // Actual B channel width (1-8)
    input wire                      cfg_enable,      // Enable sampling
    input wire                      cfg_continuous_mode, // Enable continous mode for hsync-based stream sampling
    
    // VideoBuffer write interface
    output reg                                      buf_wr_en,
    output reg [PIXEL_WIDTH-1:0]                    buf_wr_data,
    output reg                                      buf_wr_line_start,
    output reg                                      buf_wr_frame_start,
    output reg [$clog2(MAX_WIDTH*MAX_HEIGHT)-1:0]   buf_wr_addr,
    
    // Status
    output reg [15:0]                 pixel_count,
    output reg [15:0]                 line_count,
    output reg                         frame_active,
    output reg                         line_active
);

    // Sync signal edge detection
    reg hsync_d1, hsync_d2;
    reg vsync_d1, vsync_d2;
    
    wire hsync_rising  = !hsync_d2 && hsync_d1;
    wire hsync_falling = hsync_d2 && !hsync_d1;
    wire vsync_rising  = !vsync_d2 && vsync_d1;
    wire vsync_falling = vsync_d2 && !vsync_d1;
    
    // Internal state
    reg in_active_area;
    reg [15:0] h_counter;
    reg [15:0] v_counter;
    
    // Dynamic pixel data assembly with masks
    reg [PIXEL_WIDTH-1:0] pixel_data;
    wire [MAX_CHANNEL_WIDTH-1:0] r_mask = ({MAX_CHANNEL_WIDTH{1'b1}} >> (MAX_CHANNEL_WIDTH - cfg_r_width));
    wire [MAX_CHANNEL_WIDTH-1:0] g_mask = ({MAX_CHANNEL_WIDTH{1'b1}} >> (MAX_CHANNEL_WIDTH - cfg_g_width));
    wire [MAX_CHANNEL_WIDTH-1:0] b_mask = ({MAX_CHANNEL_WIDTH{1'b1}} >> (MAX_CHANNEL_WIDTH - cfg_b_width));
    
    always @(*) begin
        pixel_data = {
            vga_r & r_mask,
            vga_g & g_mask,
            vga_b & b_mask
        };
    end
    
    // Sync edge detection registers
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hsync_d1 <= 1'b0;
            hsync_d2 <= 1'b0;
            vsync_d1 <= 1'b0;
            vsync_d2 <= 1'b0;
        end else begin
            hsync_d2 <= hsync_d1;
            hsync_d1 <= vga_hsync;
            vsync_d2 <= vsync_d1;
            vsync_d1 <= vga_vsync;
        end
    end
    
    // Main sampling state machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            h_counter <= 16'd0;
            v_counter <= 16'd0;
            pixel_count <= 16'd0;
            line_count <= 16'd0;
            frame_active <= 1'b0;
            line_active <= 1'b0;
            in_active_area <= 1'b0;
            buf_wr_en <= 1'b0;
            buf_wr_data <= {PIXEL_WIDTH{1'b0}};
            buf_wr_line_start <= 1'b0;
            buf_wr_frame_start <= 1'b0;
            buf_wr_addr <= {$clog2(MAX_WIDTH*MAX_HEIGHT){1'b0}};
        end else begin
            // Default outputs
            buf_wr_en <= 1'b0;
            buf_wr_line_start <= 1'b0;
            buf_wr_frame_start <= 1'b0;
            
            if (cfg_enable) begin
                // Optional VSYNC handling - frame start (For framebuffer mode)
                if (vsync_falling) begin
                    v_counter <= 16'd0;
                    line_count <= 16'd0;
                    frame_active <= 1'b1;
                    buf_wr_frame_start <= 1'b1;
                    buf_wr_addr <= {$clog2(MAX_WIDTH*MAX_HEIGHT){1'b0}};
                end
                
                // HSYNC handling - line start
                if (hsync_falling && (frame_active || cfg_continuous_mode)) begin
                    h_counter <= 16'd0;
                    pixel_count <= 16'd0;
                    
                    // Process line if 
                    if ((v_counter < cfg_height && frame_active) || cfg_continuous_mode) begin
                        line_active <= 1'b1;
                        in_active_area <= 1'b1;
                        buf_wr_line_start <= 1'b1;
                        
                        //Only increment frame counters in frame mode
                        if (!cfg_continuous_mode) begin
                            v_counter <= v_counter + 1'b1;
                            line_count <= line_count + 1'b1;
                        end
                    end else begin
                        if (!cfg_continuous_mode) begin
                            frame_active <= 1'b0;
                        end
                        line_active <= 1'b0;
                        in_active_area <= 1'b0;
                    end
                end
                
                // Pixel sampling during active area
                if (in_active_area) begin
                    if (h_counter < cfg_width) begin
                        buf_wr_en <= 1'b1;
                        buf_wr_data <= pixel_data;
                        buf_wr_addr <= buf_wr_addr + 1'b1;
                        pixel_count <= pixel_count + 1'b1;
                        h_counter <= h_counter + 1'b1;
                    end else begin
                        in_active_area <= 1'b0;
                        line_active <= 1'b0;
                    end
                end
            end else begin
                // Reset when disabled
                h_counter <= 16'd0;
                v_counter <= 16'd0;
                pixel_count <= 16'd0;
                line_count <= 16'd0;
                frame_active <= 1'b0;
                line_active <= 1'b0;
                in_active_area <= 1'b0;
            end
        end
    end

endmodule

module RGBSampler #(
    parameter MAX_WIDTH        = 1920,
    parameter MAX_HEIGHT       = 1080,
    parameter PIXEL_WIDTH      = 24,
    parameter MAX_NUM_LINES    = 8,
    parameter USE_LINE_BUFFER  = 1,
    parameter USE_FRAME_BUFFER = 0
)(
    input wire                      clk,
    input wire                      rst_n,
    
    // VGA input signals
    input wire [7:0]                vga_r,
    input wire [7:0]                vga_g,
    input wire [7:0]                vga_b,
    input wire                      vga_hsync,
    input wire                      vga_vsync,
    
    // Configuration
    input wire [15:0]               cfg_width,
    input wire [15:0]               cfg_height,
    input wire [3:0]                cfg_num_lines,
    input wire [3:0]                cfg_r_width,
    input wire [3:0]                cfg_g_width,
    input wire [3:0]                cfg_b_width,
    input wire                      cfg_enable_sampler,
    input wire                      cfg_enable_line,
    input wire                      cfg_enable_frame,
    input wire                      cfg_continuous_mode,
    
    // VideoBuffer read interface
    input  wire                      rd_en,
    input  wire [$clog2(MAX_WIDTH*MAX_HEIGHT)-1:0] rd_addr,
    output wire [PIXEL_WIDTH-1:0]    rd_data,
    
    // Status
    output wire                      buffer_ready,
    output wire [3:0]                lines_stored,
    output wire                      frame_ready,
    output wire [15:0]               pixel_count,
    output wire [15:0]               line_count,
    output wire                      frame_active,
    output wire                      line_active
);

    // Internal signals between sampler and buffer
    wire                                        sampler_wr_en;
    wire [PIXEL_WIDTH-1:0]                      sampler_wr_data;
    wire                                        sampler_wr_line_start;
    wire                                        sampler_wr_frame_start;
    wire [$clog2(MAX_WIDTH*MAX_HEIGHT)-1:0]     sampler_wr_addr;
    
    // Instantiate RGB sampler
    rgb_sampler #(
        .MAX_R_WIDTH(8),
        .MAX_G_WIDTH(8),
        .MAX_B_WIDTH(8),
        .MAX_WIDTH(MAX_WIDTH),
        .MAX_HEIGHT(MAX_HEIGHT),
        .PIXEL_WIDTH(PIXEL_WIDTH)
    ) u_rgb_sampler (
        .clk(clk),
        .rst_n(rst_n),
        // VGA inputs
        .vga_r(vga_r),
        .vga_g(vga_g),
        .vga_b(vga_b),
        .vga_hsync(vga_hsync),
        .vga_vsync(vga_vsync),
        // Configuration
        .cfg_width(cfg_width),
        .cfg_height(cfg_height),
        .cfg_r_width(cfg_r_width),
        .cfg_g_width(cfg_g_width),
        .cfg_b_width(cfg_b_width),
        .cfg_enable(cfg_enable_sampler),
        .cfg_continuous_mode(cfg_continuous_mode),
        // Buffer interface
        .buf_wr_en(sampler_wr_en),
        .buf_wr_data(sampler_wr_data),
        .buf_wr_line_start(sampler_wr_line_start),
        .buf_wr_frame_start(sampler_wr_frame_start),
        .buf_wr_addr(sampler_wr_addr),
        // Status
        .pixel_count(pixel_count),
        .line_count(line_count),
        .frame_active(frame_active),
        .line_active(line_active)
    );
    
    // Instantiate VideoBuffer
    VideoBuffer #(
        .MAX_WIDTH(MAX_WIDTH),
        .MAX_HEIGHT(MAX_HEIGHT),
        .PIXEL_WIDTH(PIXEL_WIDTH),
        .MAX_NUM_LINES(MAX_NUM_LINES),
        .USE_LINE_BUFFER(USE_LINE_BUFFER),
        .USE_FRAME_BUFFER(USE_FRAME_BUFFER)
    ) u_video_buffer (
        .clk(clk),
        .rst_n(rst_n),
        // Configuration
        .cfg_width(cfg_width),
        .cfg_height(cfg_height),
        .cfg_num_lines(cfg_num_lines),
        .cfg_enable_line(cfg_enable_line),
        .cfg_enable_frame(cfg_enable_frame),
        // Write interface from sampler
        .wr_en(sampler_wr_en),
        .wr_data(sampler_wr_data),
        .wr_line_start(sampler_wr_line_start),
        .wr_frame_start(sampler_wr_frame_start),
        .wr_addr(sampler_wr_addr),
        // Read interface
        .rd_en(rd_en),
        .rd_addr(rd_addr),
        .rd_data(rd_data),
        // Status
        .ready(buffer_ready),
        .lines_stored(lines_stored),
        .frame_ready(frame_ready)
    );

endmodule

