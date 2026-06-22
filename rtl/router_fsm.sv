`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 25.05.2026 16:46:00
// Design Name: 
// Module Name: router_fsm
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
// MODULE: router_fsm
// DESCRIPTION: The master supervisor for the router. Sequences through 8 
//              states to coordinate packet validation, payload streaming, 
//              and parity cross-checking.
// =============================================================================
module router_fsm (
    // --- Global Control Lines ---
    input  logic       clk,                // Master system clock coordinating state transitions
    input  logic       resetn,             // Active-low global hardware reset
    
    // --- Inbound Status Indicator Flags ---
    input  logic       pkt_valid,          // Asserted by external sender indicating packet arrival/active stream
    input  logic [1:0] datain,             // Bottom 2 address bits from the bus used for early channel routing checks
    input  logic       fifo_empty0,        // High when FIFO 0 contains no data
    input  logic       fifo_empty1,        // High when FIFO 1 contains no data
    input  logic       fifo_empty2,        // High when FIFO 2 contains no data
    input  logic       fifo_full,          // Multiplexed overflow alert from the Synchronizer for the active channel
    input  logic       low_pkt_valid,      // Signal tracking if the sender dropped valid line during a full-stall
    input  logic       parity_done,        // Confirms that the full payload tracking countdown has reached zero
    input  logic       soft_reset_0,       // Synchronizer watchdog signal forcing an immediate abort for FIFO 0
    input  logic       soft_reset_1,       // Synchronizer watchdog signal forcing an immediate abort for FIFO 1
    input  logic       soft_reset_2,       // Synchronizer watchdog signal forcing an immediate abort for FIFO 2
    
    // --- Outbound Command Control Lines ---
    output logic       busy,               // Stall signal forcing the external sender to freeze transmission
    output logic       detect_add,         // Commands the Synchronizer to sample and latch the channel address
    output logic       lfd_state,          // Single-cycle pulse marking the arrival of the Header Byte
    output logic       ld_state,           // Held high to open datapath routing channels for the payload stream
    output logic       full_state,         // High exclusively when the machine is waiting out an emergency full stall
    output logic       laf_state,          // Directs registers to fetch the overrun byte from backup buffers
    output logic       write_en_reg,       // Master write enablement gating permit for datapath registers
    output logic       rst_int_reg         // Clear pulse dispatched to wipe parity engine registers back to zero
);

    // =============================================================================
    // STATE VECTOR DEFINITIONS (ONE-HOT CODING REPRESENTATION)
    // =============================================================================
    typedef enum logic [7:0] {
        DECODER_ADDRESS     = 8'b0000_0001, // State 1: Idle mode / scanning for incoming packet headers
        WAIT_TILL_EMPTY     = 8'b0000_0010, // State 2: Active path is clogged; stalling new packet entry
        LOAD_FIRST_DATA     = 8'b0000_0100, // State 3: Header processing checkpoint cycle
        LOAD_DATA           = 8'b0000_1000, // State 4: High-speed payload data streaming loop
        FIFO_FULL_STATE     = 8'b0001_0000, // State 5: Queue full emergency pause loop
        LOAD_AFTER_FULL     = 8'b0010_0000, // State 6: Leaked overrun byte recovery station
        LOAD_PARITY         = 8'b0100_0000, // State 7: Trailing checksum byte capture cycle
        CHECK_PARITY_ERROR  = 8'b1000_0000  // State 8: Calculation validation verdict cycle
    } state_e;

    state_e current_state, next_state;

    // =============================================================================
    // BLOCK 1: SEQUENTIAL STATE TRANSITION ENGINE
    // =============================================================================
    // Updates the current state of the machine on every positive clock edge.
    always_ff @(posedge clk or negedge resetn) begin : STATE_REGISTER
        if (!resetn) begin
            current_state <= DECODER_ADDRESS;  // Revert straight back to idle configuration on master reset
        end else if (soft_reset_0 || soft_reset_1 || soft_reset_2) begin
            current_state <= DECODER_ADDRESS;  // Drop everything and abort to idle if a watchdog timeout hits
        end else begin
            current_state <= next_state;        // Advance to evaluated operational path state
        end
    end


    // =============================================================================
    // BLOCK 2: COMBINATIONAL NEXT-STATE DECODER LOGIC (LATCH-FREE)
    // =============================================================================
    // Evaluates the current state and incoming status pins to compute the next target state.
    always_comb begin : NEXT_STATE_DECODER
        next_state = current_state; // Safe baseline fallback assignments completely eliminate latches
        
        unique case (current_state)
            
            DECODER_ADDRESS: begin
                if (pkt_valid) begin
                    // Read target mapping bits dynamically to evaluate path clarity
                    unique case (datain[1:0])
                        2'b00:   next_state = (fifo_empty0) ? LOAD_FIRST_DATA : WAIT_TILL_EMPTY;
                        2'b01:   next_state = (fifo_empty1) ? LOAD_FIRST_DATA : WAIT_TILL_EMPTY;
                        2'b10:   next_state = (fifo_empty2) ? LOAD_FIRST_DATA : WAIT_TILL_EMPTY;
                        default: next_state = DECODER_ADDRESS;
                    endcase
                end else begin
                    next_state = DECODER_ADDRESS;
                end
            end
            
            WAIT_TILL_EMPTY: begin
                // Check address bits dynamically to see when the clogged target FIFO unloads
                unique case (datain[1:0])
                    2'b00:   next_state = (fifo_empty0) ? LOAD_FIRST_DATA : WAIT_TILL_EMPTY;
                    2'b01:   next_state = (fifo_empty1) ? LOAD_FIRST_DATA : WAIT_TILL_EMPTY;
                    2'b10:   next_state = (fifo_empty2) ? LOAD_FIRST_DATA : WAIT_TILL_EMPTY;
                    default: next_state = WAIT_TILL_EMPTY;
                endcase
            end
            
            LOAD_FIRST_DATA: begin
                next_state = LOAD_DATA; // Mandatory single-cycle transition pulse
            end
            
            LOAD_DATA: begin
                if (fifo_full) begin
                    next_state = FIFO_FULL_STATE; // Emergency jump if queue storage saturates
                end else if (!pkt_valid) begin
                    next_state = LOAD_PARITY;     // Normal completion when data payload runs out
                end else begin
                    next_state = LOAD_DATA;       // High-speed stream loop condition stable
                end
            end
            
            FIFO_FULL_STATE: begin
                if (!fifo_full) begin
                    next_state = LOAD_AFTER_FULL; // Advance immediately when memory space clears up
                end else begin
                    next_state = FIFO_FULL_STATE; // Hold freeze loop while queue remains packed
                end
            end
            
            LOAD_AFTER_FULL: begin
                if (parity_done) begin
                    next_state = DECODER_ADDRESS; // Exit if the final trailing byte was cleared
                end else if (!low_pkt_valid) begin
                    next_state = LOAD_DATA;       // Resume streaming if more payload data follows
                end else if (low_pkt_valid) begin
                    next_state = LOAD_PARITY;     // Advance to parity if sender dropped valid during stall
                end
            end
            
            LOAD_PARITY: begin
                next_state = CHECK_PARITY_ERROR; // Mandatory single-cycle capture transition
            end
            
            CHECK_PARITY_ERROR: begin
                if (fifo_full) begin
                    next_state = FIFO_FULL_STATE; // Handle immediate full exceptions during closing calculations
                end else begin
                    next_state = DECODER_ADDRESS; // Re-enter baseline idle mode to await fresh packet strings
                end
            end
            
            default: next_state = DECODER_ADDRESS;
        endcase
    end


    // =============================================================================
    // BLOCK 3: COMBINATIONAL OUTPUT WIRE GENERATOR (LATCH-FREE DRIVERS)
    // =============================================================================
    // Generates output control command voltages based on the active state of the FSM.
    always_comb begin : OUTPUT_GENERATOR
        // Clear all output pins to absolute zeros to prevent un-intended latch synthesis behavior
        busy         = 1'b0;
        detect_add   = 1'b0;
        lfd_state    = 1'b0;
        ld_state     = 1'b0;
        full_state   = 1'b0;
        laf_state    = 1'b0;
        write_en_reg = 1'b0;
        rst_int_reg  = 1'b0;
        
        unique case (current_state)
            
            DECODER_ADDRESS: begin
                detect_add = 1'b1; // Turn on address scanning wire for the Synchronizer
                busy       = 1'b0; // System open: Ready to accept data from the outside world
            end
            
            WAIT_TILL_EMPTY: begin
                busy       = 1'b1; // Force outer sender to freeze; path is blocked
            end
            
            LOAD_FIRST_DATA: begin
                busy       = 1'b1; // Isolate bus during configuration capture cycle
                lfd_state  = 1'b1; // Command pulse marking the Header Byte capture
            end
            
            LOAD_DATA: begin
                ld_state     = 1'b1; // Lock open datapath gates for continuous FIFO writes
                write_en_reg = 1'b1; // Enable internal data processing engines
                busy         = 1'b0; // Signal to sender: "Keep pouring data!"
            end
            
            FIFO_FULL_STATE: begin
                busy       = 1'b1; // Slam the emergency brake to halt incoming traffic
                full_state = 1'b1; // Internal flag tracking active full stall conditions
            end
            
            LOAD_AFTER_FULL: begin
                busy       = 1'b1; // Keep outer stream paused while processing overrun data
                laf_state  = 1'b1; // Pull single leaked overrun byte out of backup buffer
                write_en_reg = 1'b1; // Keep data engines active to capture the byte
            end
            
            LOAD_PARITY: begin
                busy         = 1'b1; // Isolate bus to capture validation parameters
                write_en_reg = 1'b1; // Keep engine powered to lock checksum byte in
            end
            
            CHECK_PARITY_ERROR: begin
                busy        = 1'b1; // Stay busy during calculations
                rst_int_reg = 1'b1; // Flash internal clear pulse to wipe calculation registers to zero
            end
            
            default: ; // Empty default matches defensive clean design conventions
        endcase
    end

endmodule
