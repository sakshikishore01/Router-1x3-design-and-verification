`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: sakshi
// 
// Create Date: 25.05.2026 12:18:49
// Design Name: syncronizer
// Module Name: router_sync
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
// MODULE: router_sync
// DESCRIPTION: Manages channel switching, status multiplexing, and runs 
//              independent 30-cycle anti-deadlock watchdog counters.
// =============================================================================
module router_sync #(
    parameter int TIMEOUT_LIMIT = 30           // Fully parameterized timeout threshold (default 30 cycles)
)(
    // --- Global Control Bus ---
    input  logic       clk,                    // Master system clock coordinating all synchronous events
    input  logic       resetn,                 // Active-low global hardware reset
    
    // --- Central FSM Handshake Signals ---
    input  logic       detect_add,             // FSM command to sample and latch the packet target channel address
    input  logic       write_enb_reg,          // Master gating permit from FSM authorizing data writes to the FIFOs
    
    // --- Downstream External FIFO Status Lines ---
    input  logic       read_enb_0,             // Status flag checking if external device is actively reading FIFO 0
    input  logic       read_enb_1,             // Status flag checking if external device is actively reading FIFO 1
    input  logic       read_enb_2,             // Status flag checking if external device is actively reading FIFO 2
    input  logic       empty_0,                // Hardwired line from FIFO 0 signaling it contains no data
    input  logic       empty_1,                // Hardwired line from FIFO 1 signaling it contains no data
    input  logic       empty_2,                // Hardwired line from FIFO 2 signaling it contains no data
    input  logic       full_0,                 // Hardwired line from FIFO 0 signaling its memory slots are entirely packed
    input  logic       full_1,                 // Hardwired line from FIFO 1 signaling its memory slots are entirely packed
    input  logic       full_2,                 // Hardwired line from FIFO 2 signaling its memory slots are entirely packed
    
    // --- Input Data Path Extraction ---
    input  logic [1:0] datain,                 // Bottom 2 bits of header byte specifying target mapping channel
    
    // --- Central Controller Flag Outputs ---
    output logic       vld_out_0,              // Output alert indicating FIFO 0 contains a complete packet to read
    output logic       vld_out_1,              // Output alert indicating FIFO 1 contains a complete packet to read
    output logic       vld_out_2,              // Output alert indicating FIFO 2 contains a complete packet to read
    output logic [2:0] write_enb,              // Decoded parallel one-hot bus enabling write operations to targeted FIFO
    output logic       fifo_full,              // Multiplexed feedback wire tracking overflow status of active FIFO channel
    output logic       soft_reset_0,           // Watchdog timeout reset pulse used to flush stuck data out of FIFO 0
    output logic       soft_reset_1,           // Watchdog timeout reset pulse used to flush stuck data out of FIFO 1
    output logic       soft_reset_2            // Watchdog timeout reset pulse used to flush stuck data out of FIFO 2
);

    // =============================================================================
    // INTERNAL SIGNAL DECLARATIONS WITH USE
    // =============================================================================
    logic [1:0] target_addr_reg;               // Internal "sticky note" register holding the locked packet target address
    logic [4:0] timeout_cnt0;                  // Independent 5-bit watchdog counter tracking stall cycles on FIFO 0
    logic [4:0] timeout_cnt1;                  // Independent 5-bit watchdog counter tracking stall cycles on FIFO 1
    logic [4:0] timeout_cnt2;                  // Independent 5-bit watchdog counter tracking stall cycles on FIFO 2


    // =============================================================================
    // BLOCK 1: CONTINUOUS DATA REAL-TIME VALIDATION EXTRACTOR
    // =============================================================================
    // Converts internal memory structural tracking directly into immediate output read-requests.
    assign vld_out_0 = !empty_0;               // If FIFO 0 is not completely empty, valid output 0 is permanently high
    assign vld_out_1 = !empty_1;               // If FIFO 1 is not completely empty, valid output 1 is permanently high
    assign vld_out_2 = !empty_2;               // If FIFO 2 is not completely empty, valid output 2 is permanently high


    // =============================================================================
    // BLOCK 2: SEQUENTIAL PATH SELECTION LATCH (THE TRACKER ENGINE)
    // =============================================================================
    // Captures the configuration mapping bits exclusively when the FSM prompts detection.
    always_ff @(posedge clk or negedge resetn) begin : PATH_SELECTION_LATCH
        if (!resetn) begin
            target_addr_reg <= 2'b00;          // Reverts back to baseline destination FIFO 0 layout on reset
        end else if (detect_add) begin
            target_addr_reg <= datain;         // Locks address bits into safe tracking register during Header Cycle
        end
    end


    // =============================================================================
    // BLOCK 3: COMBINATIONAL FEEDBACK STATUS MULTIPLEXER (LATCH-FREE)
    // =============================================================================
    // Links the system status line to the active data processing target.
    always_comb begin : STATUS_FLAG_MULTIPLEXER
        unique case (target_addr_reg)          // Unique constraint instructs parallel high-speed hardware decoding layout
            2'b00:   fifo_full = full_0;       // Monitors full flag of FIFO 0 if target tracking matches 00
            2'b01:   fifo_full = full_1;       // Monitors full flag of FIFO 1 if target tracking matches 01
            2'b10:   fifo_full = full_2;       // Monitors full flag of FIFO 2 if target tracking matches 10
            default: fifo_full = 1'b0;         // Eliminates combinational latch generation by guaranteeing safe baseline mapping
        endcase
    end


    // =============================================================================
    // BLOCK 4: COMBINATIONAL ONE-HOT WRITE ROUTING DECODER (LATCH-FREE)
    // =============================================================================
    // Ensures write pulses are strictly contained within the targeted channel layout.
    always_comb begin : WRITE_DECODER
        write_enb = 3'b000;                    // Baseline reset assignment completely un-infers synthesis latch bugs
        if (write_enb_reg) begin
            unique case (target_addr_reg)      // Isolates active memory block mapping lines safely
                2'b00:   write_enb = 3'b001;   // Maps writing toggle bit exclusively to memory block 0 channel
                2'b01:   write_enb = 3'b010;   // Maps writing toggle bit exclusively to memory block 1 channel
                2'b10:   write_enb = 3'b100;   // Maps writing toggle bit exclusively to memory block 2 channel
                default: write_enb = 3'b000;   // Safe fallback path configuration mapping
            endcase
        end
    end


    // =============================================================================
    // BLOCK 5: SEQUENTIAL WATCHDOG PROTECTION TIMER - CHANNEL 0
    // =============================================================================
    // Counter tracking deadlock anomalies when data remains unread in FIFO 0.
    always_ff @(posedge clk or negedge resetn) begin : TIMEOUT_ENGINE_FIFO0
        if (!resetn) begin
            timeout_cnt0 <= '0;                // SystemVerilog '0 auto-fills entire vector array width to zeros
            soft_reset_0 <= 1'b0;              // Disables emergency clear lines immediately on hardware baseline reset
        end else if (vld_out_0 && !read_enb_0) begin
            if (timeout_cnt0 == (TIMEOUT_LIMIT - 1)) begin
                soft_reset_0 <= 1'b1;          // Fires targeted clear pulse on 30 continuous stuck clock cycles
                timeout_cnt0 <= '0;            // Loops execution tracking loop variables back to baseline value
            end else begin
                timeout_cnt0 <= timeout_cnt0 + 1'b1; // Increments count sequence steadily while stall is observed
                soft_reset_0 <= 1'b0;          // Holds clear line inactive during active safe scanning phase
            end
        end else begin
            timeout_cnt0 <= '0;                // Resets watch immediately if data clears or external read takes place
            soft_reset_0 <= 1'b0;              // Safety lock ensures pulse drops to low instantly
        end
    end


    // =============================================================================
    // BLOCK 6: SEQUENTIAL WATCHDOG PROTECTION TIMER - CHANNEL 1
    // =============================================================================
    // Counter tracking deadlock anomalies when data remains unread in FIFO 1.
    always_ff @(posedge clk or negedge resetn) begin : TIMEOUT_ENGINE_FIFO1
        if (!resetn) begin
            timeout_cnt1 <= '0;                // Vector clear using native clean representation syntax
            soft_reset_1 <= 1'b0;              // Keeps clearing line flat on baseline configurations
        end else if (vld_out_1 && !read_enb_1) begin
            if (timeout_cnt1 == (TIMEOUT_LIMIT - 1)) begin
                soft_reset_1 <= 1'b1;          // Fires targeted clear pulse on 30 continuous stuck clock cycles
                timeout_cnt1 <= '0;            // Erases tracked loop values instantly to complete safety execution
            end else begin
                timeout_cnt1 <= timeout_cnt1 + 1'b1; // Steps counting parameters up linearly
                soft_reset_1 <= 1'b0;          // Holds line low during scanning index tracking phases
            end
        end else begin
            timeout_cnt1 <= '0;                // Counter dropped to zero instantly if path state normalized
            soft_reset_1 <= 1'b0;              // Clear output line locked low safely
        end
    end


    // =============================================================================
    // BLOCK 7: SEQUENTIAL WATCHDOG PROTECTION TIMER - CHANNEL 2
    // =============================================================================
    // Counter tracking deadlock anomalies when data remains unread in FIFO 2.
    always_ff @(posedge clk or negedge resetn) begin : TIMEOUT_ENGINE_FIFO2
        if (!resetn) begin
            timeout_cnt2 <= '0;                // Empties target tracking bit width register components completely
            soft_reset_2 <= 1'b0;              // Safe state output configuration enforcement
        end else if (vld_out_2 && !read_enb_2) begin
            if (timeout_cnt2 == (TIMEOUT_LIMIT - 1)) begin
                soft_reset_2 <= 1'b1;          // Fires targeted clear pulse on 30 continuous stuck clock cycles
                timeout_cnt2 <= '0;            // Flushes counter register allocation directly back to zero
            end else begin
                timeout_cnt2 <= timeout_cnt2 + 1'b1; // Increments watchdog register steps
                soft_reset_2 <= 1'b0;          // Protects line against un-intended glitch triggers
            end
        end else begin
            timeout_cnt2 <= '0;                // Instant clearing on healthy verification activity markers
            soft_reset_2 <= 1'b0;              // Drops signal safe low
        end
    end

endmodule
