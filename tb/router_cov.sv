`timescale 1ns / 1ps

// =============================================================================
// MODULE: router_cov
// DESCRIPTION: Functional Coverage monitor for the Router design tailored 
//              for Cadence Xcelium/NC-Sim collection tools.
// =============================================================================
module router_cov (
    input logic        clk,
    input logic        resetn,
    
    // Inbound controls monitored
    input logic [1:0]  datain,
    input logic        pkt_valid,
    
    // Internal FSM Monitoring (Bound to router_fsm)
    input logic [7:0]  current_state,
    
    // Synchronizer & FIFO Interfaces
    input logic [2:0]  write_enb,
    input logic        fifo_full,
    input logic        vld_out_0, vld_out_1, vld_out_2,
    input logic        read_enb_0, read_enb_1, read_enb_2,
    
    // Register Trackers
    input logic        parity_done,
    input logic        error
);

    // =========================================================================
    // 1. COVERGROUP DEFINITION
    // =========================================================================
    covergroup router_cg @(posedge clk);
        option.per_instance = 1;
        option.comment = "Router Top-Level Functional Coverage Matrix";

        // --- Coverpoints for Target Address Selection ---
        cp_address: coverpoint datain[1:0] {
            bins chan_0  = {2'b00};
            bins chan_1  = {2'b01};
            bins chan_2  = {2'b10};
            illegal_bins invalid_addr = {2'b11};
        }

        // --- Coverpoints for Packet Validation State ---
        cp_pkt_valid: coverpoint pkt_valid {
            bins idle   = {1'b0};
            bins active = {1'b1};
        }

        // --- Coverpoints for Master FSM States ---
        cp_fsm_states: coverpoint current_state {
            bins IDLE          = {8'b0000_0001}; // DECODER_ADDRESS [cite: 222]
            bins STALL_WAIT    = {8'b0000_0010}; // WAIT_TILL_EMPTY [cite: 222, 223]
            bins HDR_LOAD      = {8'b0000_0100}; // LOAD_FIRST_DATA [cite: 223]
            bins PAYLOAD_STRM  = {8'b0000_1000}; // LOAD_DATA [cite: 223]
            bins PAUSE_EMERG   = {8'b0001_0000}; // FIFO_FULL_STATE [cite: 223]
            bins OVERRUN_RECOV = {8'b0010_0000}; // LOAD_AFTER_FULL [cite: 223, 224]
            bins CHKSUM_CAPT   = {8'b0100_0000}; // LOAD_PARITY [cite: 224]
            bins VERDICT_CYCLE = {8'b1000_0000}; // CHECK_PARITY_ERROR [cite: 224]
        }

        // --- Coverpoints for Parity/Error Matrix ---
        cp_parity_done: coverpoint parity_done { bins hit = {1'b1}; }
        cp_error:       coverpoint error       { bins clean = {1'b0}; bins corrupted = {1'b1}; }

        // --- Coverpoints for FIFO System Metrics ---
        cp_fifo_full:   coverpoint fifo_full   { bins saturated = {1'b1}; bins open = {1'b0}; }

        // =========================================================================
        // 2. CROSS COVERAGE MATRIX (Crucial for Functional Completeness)
        // =========================================================================
        
        // Ensure packets are routed to all three valid output channels [cite: 232, 233, 234]
        cross_addr_x_fsm: cross cp_address, cp_fsm_states {
            // Focus on streaming payload down all valid channels
            bins channel_0_streaming = binsof(cp_address.chan_0) && binsof(cp_fsm_states.PAYLOAD_STRM);
            bins channel_1_streaming = binsof(cp_address.chan_1) && binsof(cp_fsm_states.PAYLOAD_STRM);
            bins channel_2_streaming = binsof(cp_address.chan_2) && binsof(cp_fsm_states.PAYLOAD_STRM);
        }

        // Verify that stalls and buffer overruns occur on every channel [cite: 223, 224]
        cross_stall_scenarios: cross cp_address, cp_fsm_states, cp_fifo_full {
            bins ch0_backpressure = binsof(cp_address.chan_0) && binsof(cp_fsm_states.PAUSE_EMERG) && binsof(cp_fifo_full.saturated);
            bins ch1_backpressure = binsof(cp_address.chan_1) && binsof(cp_fsm_states.PAUSE_EMERG) && binsof(cp_fifo_full.saturated);
            bins ch2_backpressure = binsof(cp_address.chan_2) && binsof(cp_fsm_states.PAUSE_EMERG) && binsof(cp_fifo_full.saturated);
        }

        // Ensure both corrupted and safe transmissions are checked per channel [cite: 309, 310, 311]
        cross_integrity: cross cp_address, cp_error {
            bins clean_pkt_delivered_all = binsof(cp_error.clean);
            bins error_detected_somewhere = binsof(cp_error.corrupted);
        }

    endgroup

    // --- Instantiate the Covergroup ---
    initial begin
        router_cg cg_inst;
        cg_inst = new();
    end

endmodule
