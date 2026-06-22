`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 25.05.2026 22:31:07
// Design Name: 
// Module Name: router_reg
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
// MODULE: router_reg
// DESCRIPTION: Datapath management module. Latches header data, handles internal 
//              packet length countdown arrays, and runs live parity checks.
// =============================================================================
module router_reg (
    input  logic       clk,          // Master system clock
    input  logic       resetn,       // Active-low global hardware reset
    input  logic [7:0] datain,       // Full 8-bit parallel incoming packet data bus
    input  logic       lfd_state,    // FSM pulse marking arrival of the first Header Byte
    input  logic       ld_state,     // FSM signal authorizing active payload data loading
    input  logic       laf_state,    // FSM signal to load trailing byte after a full-stall
    input  logic       full_state,   // FSM signal indicating active emergency stall condition
    input  logic       rst_int_reg,  // FSM clear command to reset internal parity trackers
    
    output logic [7:0] d_out,        // Stabilized 8-bit data bus routed to target FIFO channels
    output logic       low_pkt_valid,// Flag tracking if sender aborted during a full stall
    output logic       parity_done,  // High when the internal packet byte counter hits zero
    output logic       error         // High if computed parity does not match trailing check-byte
);

    // --- Internal Staging Registers ---
    logic [7:0] hold_header_byte;    // Remembers the header metrics (length + address)
    logic [7:0] hold_internal_data;  // Backup buffer to hold "leaked" data during full-stalls
    logic [7:0] computed_parity;     // XOR computation engine register matrix
    logic [7:0] incoming_parity;     // Stores the trailing verification check byte
    logic [5:0] packet_length_down;  // Countdown counter tracking remaining bytes

    // =============================================================================
    // BLOCK 1: DATA OUT ROUTING PATH (COMBINATIONAL MULTIPLEXER)
    // =============================================================================
    // Steers either raw bus data or stalled backup data down into the output line.
    always_comb begin : DATA_OUT_MULTIPLEXER
        if (lfd_state)      d_out = hold_header_byte;
        else if (laf_state) d_out = hold_internal_data;
        else                d_out = datain;
    end

    // =============================================================================
    // BLOCK 2: DATA STAGING BUFFERS (SEQUENTIAL STORAGE)
    // =============================================================================
    always_ff @(posedge clk or negedge resetn) begin : DATA_STAGING_BUFFERS
        if (!resetn) begin
            hold_header_byte   <= '0;
            hold_internal_data <= '0;
            low_pkt_valid      <= 1'b0;
        end else begin
            // 1. Capture Header Configuration (Length + Address)
            if (lfd_state) begin
                hold_header_byte <= datain;
            end
            
            // 2. Capture Leaked Payload Byte during a sudden FIFO-Full transition
            if (ld_state && full_state) begin
                hold_internal_data <= datain;
            end
            
            // 3. Track if sender drops packet validation while router is frozen
            if (!ld_state && full_state && !parity_done) begin
                low_pkt_valid <= 1'b1; 
            end else if (rst_int_reg) begin
                low_pkt_valid <= 1'b0;
            end
        end
    end

    // =============================================================================
    // BLOCK 3: PACKET LENGTH COUNTDOWN DOWN-COUNTER (SEQUENTIAL)
    // =============================================================================
    // Monitors data stream and flags 'parity_done' when packet boundary is hit.
    always_ff @(posedge clk or negedge resetn) begin : COUNTDOWN_ENGINE
        if (!resetn) begin
            packet_length_down <= '0;
            parity_done        <= 1'b0;
        end else if (lfd_state) begin
            // Extract the upper 6 bits of header which contain total packet length
            packet_length_down <= datain[7:2];
            parity_done        <= 1'b0;
        end else if (ld_state && !full_state && (packet_length_down != '0)) begin
            // Decrement size count on every active, unstalled payload streaming cycle
            packet_length_down <= packet_length_down - 1'b1;
            parity_done        <= 1'b0;
        end else if (packet_length_down == '0) begin
            parity_done        <= 1'b1;
        end
    end

    // =============================================================================
    // BLOCK 4: PARITY CALCULATION ENGINE (SEQUENTIAL)
    // =============================================================================
    // Performs continuous bitwise XOR on streaming bytes to detect corruption.
    always_ff @(posedge clk or negedge resetn) begin : PARITY_ENGINE
        if (!resetn) begin
            computed_parity <= '0;
            incoming_parity <= '0;
            error           <= 1'b0;
        end else if (rst_int_reg) begin
            computed_parity <= '0;
            incoming_parity <= '0;
            error           <= 1'b0;
        end else if (lfd_state) begin
            // Seed the parity engine with the initial header byte configuration
            computed_parity <= datain;
        end else if (ld_state && !full_state) begin
            // Continuous cumulative XOR reduction step across the streaming cargo
            computed_parity <= computed_parity ^ datain;
        end else if (parity_done) begin
            // Snag the final expected parity check byte floating on the bus
            incoming_parity <= datain;
            
            // Final Verdict: Evaluate calculated parity against reported parity byte
            if (computed_parity != datain) begin
                error <= 1'b1;  // Mismatch detected! Packet is corrupted.
            end else begin
                error <= 1'b0;  // Match safe! Clean transmission data.
            end
        end
    end

endmodule
