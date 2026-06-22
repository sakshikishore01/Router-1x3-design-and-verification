`timescale 1ns / 1ps
// =============================================================================
// MODULE: router_tb
// DESCRIPTION: Automated verification testbench for router_top.
//              Generates clocks, resets, and injects clean packets to verify
//              functional routing pathways via SimVision waveforms.
// =============================================================================
module router_tb;

    // --- Testbench Clock & Timing Constants ---
    localparam CLK_PERIOD = 10; // 100 MHz clock frequency simulation

    // --- Interconnect Signals (Matching DUT Ports) ---
    logic       tb_clk;
    logic       tb_resetn;
    logic [7:0] tb_datain;
    logic       tb_pkt_valid;
    logic       tb_read_enb_0;
    logic       tb_read_enb_1;
    logic       tb_read_enb_2;
    
    logic [7:0] tb_data_out_0;
    logic [7:0] tb_data_out_1;
    logic [7:0] tb_data_out_2;
    logic       tb_vld_out_0;
    logic       tb_vld_out_1;
    logic       tb_vld_out_2;
    logic       tb_busy;
    logic       tb_error;

    // =============================================================================
    // DESIGN UNDER TEST (DUT) INSTANTIATION
    // =============================================================================
    router_top DUT (
        .clk        (tb_clk),
        .resetn     (tb_resetn),
        .datain     (tb_datain),
        .pkt_valid  (tb_pkt_valid),
        .read_enb_0 (tb_read_enb_0),
        .read_enb_1 (tb_read_enb_1),
        .read_enb_2 (tb_read_enb_2),
        .data_out_0 (tb_data_out_0),
        .data_out_1 (tb_data_out_1),
        .data_out_2 (tb_data_out_2),
        .vld_out_0  (tb_vld_out_0),
        .vld_out_1  (tb_vld_out_1),
        .vld_out_2  (tb_vld_out_2),
        .busy       (tb_busy),
        .error      (tb_error)
    );

    // =============================================================================
    // CLOCK GENERATION ENGINE
    // =============================================================================
    initial begin
        tb_clk = 1'b0;
        forever #(CLK_PERIOD/2) tb_clk = ~tb_clk;
    end

    // =============================================================================
    // AUTOMATED VERIFICATION TASKS (Reusable Macros)
    // =============================================================================
    
    // Task 1: Complete Hardware Reset Sequence
    task reset_sequence();
        begin
            @(negedge tb_clk);
            tb_resetn = 1'b0; // Engage active-low reset
            tb_datain = 8'b0;
            tb_pkt_valid = 1'b0;
            tb_read_enb_0 = 1'b0;
            tb_read_enb_1 = 1'b0;
            tb_read_enb_2 = 1'b0;
            #(CLK_PERIOD * 2);
            tb_resetn = 1'b1; // Release reset
            @(posedge tb_clk);
        end
    endtask

    // Task 2: Inject a Valid Packet onto a Specific Channel
    task send_packet(input [1:0] target_channel, input [5:0] payload_len);
        logic [7:0] header;
        logic [7:0] payload_byte;
        logic [7:0] calculated_parity;
        int i;
        begin
            // Wait until the chip is free
            while (tb_busy) @(posedge tb_clk);
            
            // Construct Header: [Length (6-bits) | Channel (2-bits)]
            header = {payload_len, target_channel};
            calculated_parity = header;
            
            // Step 1: Assert Packet Valid and drive Header Byte
            tb_pkt_valid = 1'b1;
            tb_datain = header;
            $display("[TB INFO] @ %0t ns | Sending Header to Channel %0d, Length: %0d", $time, target_channel, payload_len);
            @(posedge tb_clk);
            
            // Step 2: Stream the Payload Data Loop
            for (i = 0; i < payload_len; i++) begin
                while (tb_busy) @(posedge tb_clk); // Hold stream if full-stall occurs
                
                payload_byte = $urandom_range(8'h10, 8'hEF); // Generate safe randomized data
                calculated_parity = calculated_parity ^ payload_byte; // Continuous XOR parity accumulation
                
                tb_datain = payload_byte;
                $display("[TB DATA] @ %0t ns | Streaming Byte %0d: 0x%0h", $time, i, payload_byte);
                @(posedge tb_clk);
            end
            
            // Step 3: Stream the Final Parity Check Byte
            while (tb_busy) @(posedge tb_clk);
            tb_pkt_valid = 1'b0; // Drop valid to flag packet boundary boundary
            tb_datain = calculated_parity;
            $display("[TB PARITY] @ %0t ns | Sending Parity Check Byte: 0x%0h", $time, calculated_parity);
            @(posedge tb_clk);
            
            // Clear data bus line
            tb_datain = 8'b0;
            #(CLK_PERIOD * 2);
        end
    endtask

    // =============================================================================
    // MAIN STIMULUS EXECUTION BLOCK
    // =============================================================================
    initial begin
        // Setup waveform dumping for Cadence SimVision
        $dumpfile("router_sim.vcd");
        $dumpvars(0, router_tb);
        
        $display("[TB START] Initializing Router ASIC Functional Verification...");
        reset_sequence();
        
        // --- TEST CASE 1: Route clean packet to Channel 0 ---
        send_packet(.target_channel(2'b00), .payload_len(6'd8));
        
        // Act as receiver: Drain Channel 0 FIFO data
        if (tb_vld_out_0) begin
            tb_read_enb_0 = 1'b1;
            #(CLK_PERIOD * 10);
            tb_read_enb_0 = 1'b0;
        end

        // --- TEST CASE 2: Route clean packet to Channel 1 ---
        send_packet(.target_channel(2'b01), .payload_len(6'd5));
        
        // Act as receiver: Drain Channel 1 FIFO data
        if (tb_vld_out_1) begin
            tb_read_enb_1 = 1'b1;
            #(CLK_PERIOD * 7);
            tb_read_enb_1 = 1'b0;
        end

        // --- TEST CASE 3: Route clean packet to Channel 2 ---
        send_packet(.target_channel(2'b10), .payload_len(6'd12));
        
        // Act as receiver: Drain Channel 2 FIFO data
        if (tb_vld_out_2) begin
            tb_read_enb_2 = 1'b1;
            #(CLK_PERIOD * 14);
            tb_read_enb_2 = 1'b0;
        end

        $display("[TB END] Verification Sequence Finalized. Open SimVision to verify Waveforms.");
        $finish;
    end

endmodule
