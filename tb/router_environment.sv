`include "router_transaction.sv"
`include "router_generator.sv"
`include "router_driver.sv"
`include "router_monitor.sv"
`include "router_scoreboard.sv"

class router_environment;
    // Component handles mapping your updated class names
    router_generator   gen;
    router_driver      drv;
    monitor            mon; // Matches your simplified 'monitor' class name
    scoreboard         sb;  // Matches your simplified 'scoreboard' class name
     
    // Communication highways
    mailbox gen2drv;
    mailbox gen2scb;  // Golden path: feeds reference blueprints to scoreboard
    mailbox mon2scb;  // Output path: feeds observed actual packets to scoreboard
    event   drv_done;
     
    virtual router_interface vif;

    // Constructor: Safely builds connections and connects components
    function new(virtual router_interface vif);
        this.vif = vif;
        
        // Initialize all internal communication mailboxes
        gen2drv  = new();
        gen2scb  = new();
        mon2scb  = new();
        
        // Instantiating components matching your exact constructor arguments
        gen = new(gen2drv, drv_done);
        drv = new(vif, gen2drv, drv_done);
        mon = new(vif, mon2scb);
        sb  = new(mon2scb, gen2scb);
    endfunction

    // 1. Reset Phase: Asserts startup reset behavior via the driver
    task pre_test();
        drv.reset();
    endtask

    // 2. Main Test Phase: Executes parallel threads
    task test();
        fork
            gen.main();
            drv.main();
            mon.run();  // Corrected to use your updated 'run' task name
            sb.run();   // Corrected to use your updated 'run' task name
        join_any
    endtask

    // 3. Cleanup Phase: Checks for traffic draining before shutting down
    task post_test();
        // Wait until the scoreboard checks the same number of packets the generator created
        wait(gen.num_packets == sb.packets_verified); // Corrected property handle
        #100ns; // Small grace delay to complete printing final log lines
        
        $display("\n============= FINAL VERIFICATION STATUS =============");
        $display("   Total Randomized Packets Verified: %0d", sb.packets_verified);
        $display("   Total Interface Violations/Errors: %0d", sb.error_count);
        $display("=====================================================\n");
    endtask

    // Core execution flow wrapper
    task run(int num_pkts);
        gen.num_packets = num_pkts;
        pre_test();
        test();
        post_test();
    endtask
endclass
