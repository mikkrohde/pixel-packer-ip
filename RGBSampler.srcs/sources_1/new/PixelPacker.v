`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// Create Date: 21.12.2025 21:43:12
// Design Name:
// Module Name: PixelPacker
// Project Name:
// Target Devices:
// Tool Versions:
// Description: Packs raw RGB input signals into 24-bit pixels using
//              configurable channel widths and masks. Pure VPU streaming
//              stage - no buffering. Driven by SyncDecoder VPU timing.
//
// Dependencies: SyncDecoder (external timing source)
//
// Revision:
// Revision 3.0 - Refactored from RGBSampler to pure pixel packer
//                Removed VideoBuffer dependency
//                Clean VPU stream in/out interface
//
//////////////////////////////////////////////////////////////////////////////////

module PixelPacker #(
    parameter PIXEL_WIDTH       = 24,
    parameter MAX_CHANNEL_WIDTH = 8
)(
    input wire                      clk,
    input wire                      rst_n,

    // Raw RGB input signals (active during VPU_in_valid)
    input wire [MAX_CHANNEL_WIDTH-1:0]  in_vga_r,
    input wire [MAX_CHANNEL_WIDTH-1:0]  in_vga_g,
    input wire [MAX_CHANNEL_WIDTH-1:0]  in_vga_b,

    // VPU Input Stream (from SyncDecoder)
    input wire                      VPU_in_valid,
    input wire                      VPU_in_line_start,
    input wire                      VPU_in_frame_start,
    input wire                      VPU_in_interlaced,
    input wire                      VPU_in_field_id,
    input wire [11:0]               VPU_in_h_active,
    input wire [11:0]               VPU_in_v_active,

    // Configuration
    input wire [3:0]                VPU_cfg_r_width,
    input wire [3:0]                VPU_cfg_g_width,
    input wire [3:0]                VPU_cfg_b_width,
    input wire                      VPU_cfg_enable,

    // VPU Output Stream (to Deinterlacer / next stage)
    output reg                      VPU_out_valid,
    output reg [PIXEL_WIDTH-1:0]    VPU_out_pixel,
    output reg                      VPU_out_line_start,
    output reg                      VPU_out_frame_start,
    output reg                      VPU_out_interlaced,
    output reg                      VPU_out_field_id,
    output reg [11:0]               VPU_out_h_active,
    output reg [11:0]               VPU_out_v_active
);

    // =========================================================================
    // Channel masking
    // =========================================================================
    // Masks the upper bits of each channel based on configured width.
    // e.g. cfg_r_width=5 on an 8-bit input: mask = 8'b00011111
    //      This allows supporting sources with fewer than 8 bits per channel
    //      (e.g. 5-bit R from a 15-bit RGB source like PC Engine).

    wire [MAX_CHANNEL_WIDTH-1:0] r_mask = ({MAX_CHANNEL_WIDTH{1'b1}} >> (MAX_CHANNEL_WIDTH - VPU_cfg_r_width));
    wire [MAX_CHANNEL_WIDTH-1:0] g_mask = ({MAX_CHANNEL_WIDTH{1'b1}} >> (MAX_CHANNEL_WIDTH - VPU_cfg_g_width));
    wire [MAX_CHANNEL_WIDTH-1:0] b_mask = ({MAX_CHANNEL_WIDTH{1'b1}} >> (MAX_CHANNEL_WIDTH - VPU_cfg_b_width));

    wire [MAX_CHANNEL_WIDTH-1:0] r_masked = in_vga_r & r_mask;
    wire [MAX_CHANNEL_WIDTH-1:0] g_masked = in_vga_g & g_mask;
    wire [MAX_CHANNEL_WIDTH-1:0] b_masked = in_vga_b & b_mask;

    wire [PIXEL_WIDTH-1:0] packed_pixel = {r_masked, g_masked, b_masked};

    // =========================================================================
    // VPU Stream Pipeline Register
    // =========================================================================
    // Single pipeline stage: registers the packed pixel and all VPU control
    // signals. Adds 1 clock cycle of latency.

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            VPU_out_valid       <= 1'b0;
            VPU_out_pixel       <= {PIXEL_WIDTH{1'b0}};
            VPU_out_line_start  <= 1'b0;
            VPU_out_frame_start <= 1'b0;
            VPU_out_interlaced  <= 1'b0;
            VPU_out_field_id    <= 1'b0;
            VPU_out_h_active    <= 12'd0;
            VPU_out_v_active    <= 12'd0;
        end else begin
            if (VPU_cfg_enable) begin
                VPU_out_valid       <= VPU_in_valid;
                VPU_out_pixel       <= packed_pixel;
                VPU_out_line_start  <= VPU_in_line_start;
                VPU_out_frame_start <= VPU_in_frame_start;
                VPU_out_interlaced  <= VPU_in_interlaced;
                VPU_out_field_id    <= VPU_in_field_id;
                VPU_out_h_active    <= VPU_in_h_active;
                VPU_out_v_active    <= VPU_in_v_active;
            end else begin
                // Disabled: pass through raw pixels without masking,
                // allows downstream to still receive data for bypass/debug
                VPU_out_valid       <= VPU_in_valid;
                VPU_out_pixel       <= {in_vga_r, in_vga_g, in_vga_b};
                VPU_out_line_start  <= VPU_in_line_start;
                VPU_out_frame_start <= VPU_in_frame_start;
                VPU_out_interlaced  <= VPU_in_interlaced;
                VPU_out_field_id    <= VPU_in_field_id;
                VPU_out_h_active    <= VPU_in_h_active;
                VPU_out_v_active    <= VPU_in_v_active;
            end
        end
    end

endmodule