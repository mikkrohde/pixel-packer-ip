`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Create Date: 21.12.2025 21:43:12
// Design Name:
// Module Name: RGBSampler
// Project Name:
// Target Devices:
// Tool Versions:
// Description: Video sampler that captures RGB signals and packs them into
//              pixels, driven by SyncDecoder timing. Writes to VideoBuffer.
//
// Dependencies: VideoBuffer, SyncDecoder (external timing source)
//
// Revision:
// Revision 2.0 - Refactored to use SyncDecoder VPU output for timing
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module rgb_sampler #(
    parameter MAX_R_WIDTH       = 8,
    parameter MAX_G_WIDTH       = 8,
    parameter MAX_B_WIDTH       = 8,
    parameter MAX_WIDTH         = 1920,
    parameter MAX_HEIGHT        = 1080,
    parameter PIXEL_WIDTH       = 24,
    parameter MAX_CHANNEL_WIDTH = 8
)(
    input wire                      clk,
    input wire                      rst_n,

    // Raw RGB input signals
    input wire [MAX_R_WIDTH-1:0]    in_vga_r,
    input wire [MAX_G_WIDTH-1:0]    in_vga_g,
    input wire [MAX_B_WIDTH-1:0]    in_vga_b,

    // SyncDecoder VPU timing inputs
    input wire                      VPU_in_valid,
    input wire                      VPU_in_line_start,
    input wire                      VPU_in_frame_start,

    // Configuration
    input wire [3:0]                VPU_cfg_r_width,
    input wire [3:0]                VPU_cfg_g_width,
    input wire [3:0]                VPU_cfg_b_width,
    input wire                      VPU_cfg_enable,

    // VideoBuffer write interface
    output reg                                      buf_wr_en,
    output reg [PIXEL_WIDTH-1:0]                    buf_wr_data,
    output reg                                      buf_wr_line_start,
    output reg                                      buf_wr_frame_start,
    output reg [$clog2(MAX_WIDTH*MAX_HEIGHT)-1:0]   buf_wr_addr,

    // Status
    output reg [15:0]   pixel_count,
    output reg [15:0]   line_count,
    output reg          frame_active,
    output reg          line_active
);

    // Dynamic pixel data assembly with masks
    wire [MAX_CHANNEL_WIDTH-1:0] r_mask = ({MAX_CHANNEL_WIDTH{1'b1}} >> (MAX_CHANNEL_WIDTH - VPU_cfg_r_width));
    wire [MAX_CHANNEL_WIDTH-1:0] g_mask = ({MAX_CHANNEL_WIDTH{1'b1}} >> (MAX_CHANNEL_WIDTH - VPU_cfg_g_width));
    wire [MAX_CHANNEL_WIDTH-1:0] b_mask = ({MAX_CHANNEL_WIDTH{1'b1}} >> (MAX_CHANNEL_WIDTH - VPU_cfg_b_width));

    wire [PIXEL_WIDTH-1:0] pixel_data = {
        in_vga_r & r_mask,
        in_vga_g & g_mask,
        in_vga_b & b_mask
    };

    // Main sampling logic - driven by SyncDecoder timing
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_count     <= 16'd0;
            line_count      <= 16'd0;
            frame_active    <= 1'b0;
            line_active     <= 1'b0;
            buf_wr_en       <= 1'b0;
            buf_wr_data     <= {PIXEL_WIDTH{1'b0}};
            buf_wr_line_start  <= 1'b0;
            buf_wr_frame_start <= 1'b0;
            buf_wr_addr     <= {$clog2(MAX_WIDTH*MAX_HEIGHT){1'b0}};
        end else begin
            // Default outputs
            buf_wr_en          <= 1'b0;
            buf_wr_line_start  <= 1'b0;
            buf_wr_frame_start <= 1'b0;

            if (VPU_cfg_enable) begin
                // Frame start from SyncDecoder
                if (VPU_in_frame_start) begin
                    line_count  <= 16'd0;
                    frame_active <= 1'b1;
                    buf_wr_frame_start <= 1'b1;
                    buf_wr_addr <= {$clog2(MAX_WIDTH*MAX_HEIGHT){1'b0}};
                end

                // Line start from SyncDecoder
                if (VPU_in_line_start) begin
                    pixel_count <= 16'd0;
                    line_active <= 1'b1;
                    buf_wr_line_start <= 1'b1;
                    line_count <= line_count + 1'b1;
                end

                // Pixel sampling - SyncDecoder tells us when pixels are valid
                if (VPU_in_valid) begin
                    buf_wr_en   <= 1'b1;
                    buf_wr_data <= pixel_data;
                    buf_wr_addr <= buf_wr_addr + 1'b1;
                    pixel_count <= pixel_count + 1'b1;
                end else begin
                    line_active <= 1'b0;
                end
            end else begin
                // Reset when disabled
                pixel_count  <= 16'd0;
                line_count   <= 16'd0;
                frame_active <= 1'b0;
                line_active  <= 1'b0;
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

    // Raw RGB input signals
    input wire [7:0]                in_vga_r,
    input wire [7:0]                in_vga_g,
    input wire [7:0]                in_vga_b,

    // SyncDecoder VPU timing inputs
    input wire                      VPU_in_valid,
    input wire                      VPU_in_line_start,
    input wire                      VPU_in_frame_start,

    // Configuration
    input wire [3:0]                VPU_cfg_num_lines,
    input wire [3:0]                VPU_cfg_r_width,
    input wire [3:0]                VPU_cfg_g_width,
    input wire [3:0]                VPU_cfg_b_width,
    input wire                      VPU_cfg_enable_sampler,
    input wire                      VPU_cfg_enable_line,
    input wire                      VPU_cfg_enable_frame,
    input wire [15:0]               VPU_cfg_width,
    input wire [15:0]               VPU_cfg_height,

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
        .in_vga_r(in_vga_r),
        .in_vga_g(in_vga_g),
        .in_vga_b(in_vga_b),
        .VPU_in_valid(VPU_in_valid),
        .VPU_in_line_start(VPU_in_line_start),
        .VPU_in_frame_start(VPU_in_frame_start),
        .VPU_cfg_r_width(VPU_cfg_r_width),
        .VPU_cfg_g_width(VPU_cfg_g_width),
        .VPU_cfg_b_width(VPU_cfg_b_width),
        .VPU_cfg_enable(VPU_cfg_enable_sampler),
        .buf_wr_en(sampler_wr_en),
        .buf_wr_data(sampler_wr_data),
        .buf_wr_line_start(sampler_wr_line_start),
        .buf_wr_frame_start(sampler_wr_frame_start),
        .buf_wr_addr(sampler_wr_addr),
        .pixel_count(pixel_count),
        .line_count(line_count),
        .frame_active(frame_active),
        .line_active(line_active)
    );

    // Instantiate VideoBuffer
    VPU_VideoBuffer #(
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
        .VPU_cfg_width(VPU_cfg_width),
        .VPU_cfg_height(VPU_cfg_height),
        .VPU_cfg_num_lines(VPU_cfg_num_lines),
        .VPU_cfg_enable_line(VPU_cfg_enable_line),
        .VPU_cfg_enable_frame(VPU_cfg_enable_frame),
        .wr_en(sampler_wr_en),
        .wr_data(sampler_wr_data),
        .wr_line_start(sampler_wr_line_start),
        .wr_frame_start(sampler_wr_frame_start),
        .wr_addr(sampler_wr_addr),
        .rd_en(rd_en),
        .rd_addr(rd_addr),
        .rd_data(rd_data),
        .buffer_ready(buffer_ready),
        .lines_stored(lines_stored),
        .frame_ready(frame_ready)
    );

endmodule
