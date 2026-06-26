`timescale 1ns / 1ps
`include "router_interface.sv"
`include "router_environment.sv"

module tb_top;

    // 1. Generate master clock matrix line (100MHz baseline)
    bit clk;
    always #5 clk = ~clk; 

    // 2. Instantiate SystemVerilog Interface Wrapper
    router_interface inf(clk);

    // Declaring the environment handle at module level for optimal scope visibility
    router_environment env;

    // 3. Connect your physical core top module DUT wrapper
router_cov cov_monitor_inst (
    .clk           (clk),
    .resetn        (resetn),
    .datain        (datain),
    .pkt_valid     (pkt_valid),
    .current_state (DUT.fsm_block.current_state), // Hierarchical probe into FSM
    .write_enb     (DUT.write_enb),
    .fifo_full     (DUT.fifo_full),
    .vld_out_0     (vld_out_0),
    .vld_out_1     (vld_out_1),
    .vld_out_2     (vld_out_2),
    .read_enb_0    (read_enb_0),
    .read_enb_1    (read_enb_1),
    .read_enb_2    (read_enb_2),
    .parity_done   (DUT.reg_block.parity_done),   // Hierarchical probe into Register module
    .error         (error)
);
    // 4. Verification Test Execution Block
    initial begin
        $display("[TOP_ROOT] Initializing Object-Oriented Layered Test Environment...");
        
        // Build the environment object and hook up physical wires
        env = new(inf);
        
        // Execute a regression suite testing 20 fully randomized packets across channels
        // This task will block and manage its own completion loop internally
        env.run(20);
        
        // Once the environment finishes draining and analyzing all traffic data safely,
        // it hands control back here to gracefully wrap up the terminal process
        $display("[TOP_ROOT] Verification suite run successfully finished. Shutting down.");
        $finish; 
    end

    // Waveform generation dumping hooks for Cadence SimVision Viewer
    initial begin
        $dumpfile("router_layered_sim.vcd");
        $dumpvars(0, tb_top);
    end

endmodule
