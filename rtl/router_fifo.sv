`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 26.05.2026 01:29:34
// Design Name: 
// Module Name: router_fifo
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


// =============================================================================
// MODULE: router_fifo
// DESCRIPTION: 16x8 circular memory array implementing First-In, First-Out queue
//              mechanics with dual pointer comparison status flags.
// =============================================================================
module router_fifo #(
    parameter DEPTH = 16,
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4 // 2^4 = 16 memory locations
)(
    input  logic                    clk,          // Master system clock
    input  logic                    resetn,       // Active-low global hardware reset
    input  logic                    soft_reset,   // Watchdog timeout reset pulse from synchronizer
    input  logic                    write_enb,    // Write permit authorized by synchronizer routing
    input  logic                    read_enb,     // Read permit driven by external device receiver
    input  logic                    lfd_state,    // Master packet marker pulse from FSM
    input  logic [DATA_WIDTH-1:0]   d_in,         // 8-bit parallel data from router_reg

    output logic [DATA_WIDTH-1:0]   d_out,        // Output data bus linked to external output pins
    output logic                    vld_out,      // Valid Data Out flag (Alerts the Watchdog)
    output logic                    full,         // Queue full indicator (Slam entry brakes)
    output logic                    empty         // Queue empty indicator (No data to fetch)
);

    // --- Core Memory Array & Tracking Pointers ---
    logic [DATA_WIDTH-1:0] mem_array [DEPTH-1:0];
    logic [ADDR_WIDTH:0]   write_ptr;  // 5 bits wide (4 bits for address, 1 extra bit for wrap-around check)
    logic [ADDR_WIDTH:0]   read_ptr;   // 5 bits wide (4 bits for address, 1 extra bit for wrap-around check)
    
    // --- Internal Latch Tracking Register ---
    logic                  lfd_state_reg; // The "Sticky Note" flip-flop

    // =============================================================================
    // BLOCK 1: THE PACKET LIFECYCLE TRACKER (The "Sticky Note" Register)
    // =============================================================================
    // This flip-flop catches the single-cycle 'lfd_state' alarm pulse from the FSM
    // and stays high to remember that a real, active packet transmission is alive.
    always_ff @(posedge clk or negedge resetn) begin : PACKET_LIFECYCLE_TRACKER
        if (!resetn) begin
            lfd_state_reg <= 1'b0;
        end else if (soft_reset) begin
            lfd_state_reg <= 1'b0; // Rip the sticky note off if the watchdog forces a reset!
        end else if (lfd_state) begin
            lfd_state_reg <= 1'b1; // Lock to '1' the instant the header byte arrives
        end
    end

    // =============================================================================
    // BLOCK 2: SEQUENTIAL CORE MEMORY WRITE DRIVE
    // =============================================================================
    always_ff @(posedge clk) begin : MEMORY_WRITE_PORT
        if (write_enb && !full) begin
            // Index the array using only the lower 4 bits of the 5-bit pointer
            mem_array[write_ptr[ADDR_WIDTH-1:0]] <= d_in;
        end
    end

    // =============================================================================
    // BLOCK 3: COMBINATIONAL MEMORY READ DRIVE (LOW-LATENCY TRANSPARENT)
    // =============================================================================
    always_comb begin : MEMORY_READ_PORT
        if (empty) begin
            d_out = 8'bz; // High-impedance floating state if queue contains no data
        end else begin
            d_out = mem_array[read_ptr[ADDR_WIDTH-1:0]];
        end
    end

    // =============================================================================
    // BLOCK 4: POINTER CALCULATOR PATHS
    // =============================================================================
    always_ff @(posedge clk or negedge resetn) begin : POINTER_ENGINE
        if (!resetn) begin
            write_ptr <= '0;
            read_ptr  <= '0;
        end else if (soft_reset) begin
            write_ptr <= '0; // Complete internal pointer wipeout on watchdog timeout
            read_ptr  <= '0;
        end else begin
            // Increment write pointer when authorized and safe
            if (write_enb && !full) begin
                write_ptr <= write_ptr + 1'b1;
            end
            
            // Increment read pointer when authorized and safe
            if (read_enb && !empty) begin
                read_ptr <= read_ptr + 1'b1;
            end
        end
    end

    // =============================================================================
    // BLOCK 5: COMBINATIONAL FLAGS GENERATION MATRIX
    // =============================================================================
    always_comb begin : STATUS_FLAGS_GENERATOR
        // Empty calculation: Pointers match exactly across all 5 bits
        empty = (write_ptr == read_ptr);
        
        // Full calculation: MSB is opposite, but lower 4 bits match perfectly
        full  = (write_ptr[ADDR_WIDTH] != read_ptr[ADDR_WIDTH]) && 
                (write_ptr[ADDR_WIDTH-1:0] == read_ptr[ADDR_WIDTH-1:0]);
    end

    // =============================================================================
    // BLOCK 6: OUTPUT VALIDATION GATE (Using lfd_state_reg)
    // =============================================================================
    // Instead of making vld_out a direct copy of (!empty), we gate it with our 
    // tracker. The output is ONLY valid if the FIFO contains data AND the internal
    // register confirms that a real packet has officially started.
    assign vld_out = (!empty) && lfd_state_reg;

endmodule
