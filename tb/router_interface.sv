`timescale 1ns / 1ps

interface router_interface(input bit clk);
    // Inbound Stimulus Driving Lines (Driven by Driver Component)
    logic        resetn;
    logic [7:0]  datain;
    logic        pkt_valid;
    
    // Outbound Response Lines (Sampled by Monitors)
    logic        busy;
    logic        error;
    
    // Three Independent Output Routing Channel Ports
    logic        read_enb_0;
    logic [7:0]  data_out_0;
    logic        vld_out_0;
    
    logic        read_enb_1;
    logic [7:0]  data_out_1;
    logic        vld_out_1;
    
    logic        read_enb_2;
    logic [7:0]  data_out_2;
    logic        vld_out_2;

    // Clocking block for uniform, race-condition free stimulus driving
    clocking drv_cb @(negedge clk);
        output resetn;
        output datain;
        output pkt_valid;
        input  busy;
    endclocking

    // Clocking block for safe, synchronized monitoring
    clocking mon_cb @(posedge clk);
        input  resetn;
        input  datain;
        input  pkt_valid;
        input  busy;
        input  error;
        input  data_out_0; input vld_out_0; output read_enb_0;
        input  data_out_1; input vld_out_1; output read_enb_1;
        input  data_out_2; input vld_out_2; output read_enb_2;
    endclocking
endinterface
