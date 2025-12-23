`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 23.12.2025 15:10:28
// Design Name: 
// Module Name: tb_rgb_sampler_continuous
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module tb_rgb_sampler_continuous;

    reg clk = 0;
    reg rst_n = 0;

    // VGA stimulus
    reg [7:0] vga_r, vga_g, vga_b;
    reg       vga_hsync, vga_vsync;

    // Config
    reg [15:0] cfg_width;
    reg [15:0] cfg_height;
    reg [3:0]  cfg_num_lines;
    reg [3:0]  cfg_r_width;
    reg [3:0]  cfg_g_width;
    reg [3:0]  cfg_b_width;
    reg        cfg_enable_sampler;
    reg        cfg_enable_line;
    reg        cfg_enable_frame;
    reg        cfg_continuous_mode;

    // Read side
    reg  rd_en;
    reg  [$clog2(1920*1080)-1:0] rd_addr;
    wire [23:0] rd_data;

    // Status
    wire buffer_ready;
    wire [3:0] lines_stored;
    wire frame_ready;
    wire [15:0] pixel_count;
    wire [15:0] line_count;
    wire frame_active;
    wire line_active;

    // Clock
    always #5 clk = ~clk; // 100 MHz

    // DUT
    RGBSampler #(
        .MAX_WIDTH(640),
        .MAX_HEIGHT(480),
        .PIXEL_WIDTH(24),
        .MAX_NUM_LINES(8),
        .USE_LINE_BUFFER(1),
        .USE_FRAME_BUFFER(0)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),

        .vga_r(vga_r),
        .vga_g(vga_g),
        .vga_b(vga_b),
        .vga_hsync(vga_hsync),
        .vga_vsync(vga_vsync),

        .cfg_width(cfg_width),
        .cfg_height(cfg_height),
        .cfg_num_lines(cfg_num_lines),
        .cfg_r_width(cfg_r_width),
        .cfg_g_width(cfg_g_width),
        .cfg_b_width(cfg_b_width),
        .cfg_enable_sampler(cfg_enable_sampler),
        .cfg_enable_line(cfg_enable_line),
        .cfg_enable_frame(cfg_enable_frame),
        .cfg_continuous_mode(cfg_continuous_mode),

        .rd_en(rd_en),
        .rd_addr(rd_addr),
        .rd_data(rd_data),

        .buffer_ready(buffer_ready),
        .lines_stored(lines_stored),
        .frame_ready(frame_ready),
        .pixel_count(pixel_count),
        .line_count(line_count),
        .frame_active(frame_active),
        .line_active(line_active)
    );

    // ----------------------------------------------------------------
    // Helper: Drive single HSYNC-delimited line (no VSYNC)
    // ----------------------------------------------------------------
    task drive_single_line;
        input integer W;
        input [7:0] base_r, base_g, base_b;
        integer x;
    begin
        // HSYNC pulse
        vga_hsync = 0;
        vga_r = 0; vga_g = 0; vga_b = 0;
        @(posedge clk);
        vga_hsync = 1;
        @(posedge clk);  // Ensure clean falling edge detection
        
        // Active pixels
        for (x = 0; x < W; x = x + 1) begin
            vga_r = base_r + x[7:0];
            vga_g = base_g + x[7:0]; 
            vga_b = base_b + x[7:0];
            @(posedge clk);
        end
        
        // Line blanking
        vga_r = 0; vga_g = 0; vga_b = 0;
        repeat (10) @(posedge clk);
    end
    endtask

    // -------------------------------------------------------------------
    // REALISTIC LINE BUFFER TEST: Continuous streaming
    // Fills buffer, then reads oldest line while sampling the second line
    // -------------------------------------------------------------------
    task run_continuous_stream_test;
        input [3:0] test_r_width;
        input [3:0] test_g_width;
        input [3:0] test_b_width;
        input [3:0] test_num_lines;
        integer cycle;
        integer timeout_counter;
    begin
        $display("=== CONTINUOUS STREAM TEST: R=%0d G=%0d B=%0d, %0d lines ===", 
                 test_r_width, test_g_width, test_b_width, test_num_lines);
    
        // Config
        cfg_width          = 16;
        cfg_height         = 1000;
        cfg_num_lines      = test_num_lines;
        cfg_r_width        = test_r_width;
        cfg_g_width        = test_g_width;
        cfg_b_width        = test_b_width;
        cfg_enable_sampler = 1;
        cfg_enable_line    = 1;
        cfg_enable_frame   = 0;
        cfg_continuous_mode = 1; //Enable continuous hsync-based sampling
    
        // Reset
        rst_n = 0;
        vga_r = 0; vga_g = 0; vga_b = 0;
        vga_hsync = 1;
        vga_vsync = 1;
        rd_en = 0; rd_addr = 0;
        repeat (10) @(posedge clk);
        rst_n = 1;
        repeat (10) @(posedge clk);
        
    
        // Phase 1: Fill buffer (with timeout)
        $display("Phase 1: Filling %0d lines...", cfg_num_lines);
        repeat (cfg_num_lines) begin
            drive_single_line(cfg_width, 8'h10, 8'h20, 8'h30);
        end
        
        // Wait for buffer_ready with timeout counter
        timeout_counter = 0;
        while (!buffer_ready && timeout_counter < 2000) begin
            @(posedge clk);
            timeout_counter = timeout_counter + 1;
        end
        
        if (!buffer_ready) begin
            $display("ERROR: buffer_ready timeout after %0d cycles!", timeout_counter);
            $finish;
        end
        
        if (lines_stored > cfg_num_lines || lines_stored == 0) begin
            $display("ERROR: lines_stored=%0d out of range (1..%0d)", lines_stored, cfg_num_lines);
            $finish;
        end
        $display("Buffer ready after %0d cycles: lines_stored=%0d", timeout_counter, lines_stored);
    
        // Phase 2: Continuous streaming with timeout protection
        $display("Phase 2: Continuous streaming (4 cycles)...");
        for (cycle = 0; cycle < 4; cycle = cycle + 1) begin
            $display("  Cycle %0d: Writing new line (Line %0d)...", cycle, cfg_num_lines + cycle);
            
            // Write new line
            drive_single_line(cfg_width, 8'h40 + cycle, 8'h50, 8'h60);
            
            // Read oldest line with timeout
            timeout_counter = 0;
            while (!buffer_ready && timeout_counter < 1000) begin
                @(posedge clk);
                timeout_counter = timeout_counter + 1;
            end
            
            if (!buffer_ready) begin
                $display("ERROR: buffer_ready timeout in read phase, cycle %0d", cycle);
                $finish;
            end
            
            $display("  Cycle %0d: Reading oldest line (lines_stored=%0d):", cycle, lines_stored);
            rd_en = 1; 
            rd_addr = 0;
            repeat (cfg_width) begin
                @(posedge clk);
                if (rd_data[23:16] !== 8'h00) begin
                    $display("    BUF[%0d]=0x%06h", rd_addr, rd_data);
                end
                rd_addr = rd_addr + 1;
            end
            rd_en = 0; 
            rd_addr = 0;
        end
        
        $display("CONTINUOUS STREAM TEST PASSED \n");
    end
    endtask
    
    // ----------------------------------------------------------------
    // DEBUG: Dump all signals to VCD + data file
    // ----------------------------------------------------------------
    reg [31:0] debug_time_ns;
    always @(posedge clk) begin
        debug_time_ns = $time;
        debug_dump(debug_time_ns);
    end
    
    integer debug_file;
    initial begin
        debug_file = $fopen("rgb_sampler_debug_continuous.txt", "w");
        if (debug_file == 0) begin
            $display("FATAL: Cannot open rgb_sampler_debug_frame.txt!");
            $finish;
        end
        $fdisplay(debug_file, "Time(ns) | frame_act | line_cnt | pix_cnt | v_cnt | h_cnt | in_act | buf_rdy | lines_st | rd_en | rd_ad | rd_data");
        $fdisplay(debug_file, "---------------------------------------------------------------------------------------");
    end
    
    task debug_dump;
        input [31:0] time_ns;
    begin
        $fdisplay(debug_file, "%7d | %7b | %7d | %6d | %4d | %5d | %5b | %7b | %8d | %4b | %5d | 0x%06h",
                  time_ns,
                  frame_active, line_count, pixel_count, 
                  dut.u_rgb_sampler.v_counter, dut.u_rgb_sampler.h_counter, 
                  dut.u_rgb_sampler.in_active_area,
                  buffer_ready, lines_stored, rd_en, rd_addr, rd_data);
    end
    endtask
    
    // VCD dump
    initial begin
        $dumpfile("rgb_sampler_debug_continuous.vcd");
        $dumpvars(1, tb_rgb_sampler_continuous);
    end

    
    // ----------------------------------------------------------------
    // Main test sequence
    // ----------------------------------------------------------------
    integer w;

    initial begin
        // Default cfgs
        cfg_width          = 32;
        cfg_height         = 24;
        cfg_num_lines      = 2;
        cfg_r_width        = 8;
        cfg_g_width        = 8;
        cfg_b_width        = 8;
        cfg_enable_sampler = 0;
        cfg_enable_line    = 1;
        cfg_enable_frame   = 0;
        cfg_continuous_mode = 1;
        rd_en              = 0;
        rd_addr            = 0;

        vga_r = 0; vga_g = 0; vga_b = 0;
        vga_hsync = 1; vga_vsync = 1;

        repeat (20) @(posedge clk);

        // Test 2: REALISTIC LINE BUFFER - continuous streaming
        $display("=");
        $display("TEST PHASE 2: CONTINUOUS STREAMING LINE BUFFER");
        $display("=");
        run_continuous_stream_test(8,8,8,4);  // 8-bit RGB, 4-line buffer
        run_continuous_stream_test(4,6,8,2);  // Mixed RGB widths, 2-line buffer

        $display("=");
        $display("ALL TESTS COMPLETED SUCCESSFULLY");
        $display("=");
        #1000 $finish;
    end

endmodule
