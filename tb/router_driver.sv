class router_driver;
    virtual router_interface vif;
    mailbox gen2drv;
    event   drv_done;

    function new(virtual router_interface vif, mailbox gen2drv, event drv_done);
        this.vif     = vif;
        this.gen2drv = gen2drv;
        this.drv_done = drv_done;
    endfunction

    task reset();
        $display("[DRIVER] Initiating hardware global master reset...");
        vif.drv_cb.resetn    <= 1'b0;
        vif.drv_cb.pkt_valid <= 1'b0;
        vif.drv_cb.datain    <= 8'h00;
        repeat(3) @(vif.drv_cb);
        vif.drv_cb.resetn    <= 1'b1;
        $display("[DRIVER] Hardware reset released successfully.");
    endtask

    task main();
        forever begin
            router_transaction tx;
            gen2drv.get(tx);
            
            // Wait out backpressure constraints if FSM is currently busy  (header phase)
            while(vif.drv_cb.busy) @(vif.drv_cb);  //DYNAMIC CONTROL

 
           
            $display("[DRIVER] Launching injection of Packet Header: 0x%0h", tx.header);
            vif.drv_cb.pkt_valid <= 1'b1;
            vif.drv_cb.datain    <= tx.header;
            @(vif.drv_cb);  //DATA STABILITY
            
            // Unload randomized payload contents (payload phase)
            foreach(tx.payload[i]) begin
//when busy=1, gets trapped in the loop and keeps waiting fir clock cycles therefore computer never reads the line 2, so no data injected and wires stay still BUT when busy=0, driver arrices at line 1 and sees biys low so breaks out of line 1 instantly. NOw it reaches line 2 (it executes) and data is injected intot he datain bus.

                while(vif.drv_cb.busy) @(vif.drv_cb); // line 1  - wait out a stall
                vif.drv_cb.datain <= tx.payload[i];    //line 2
                @(vif.drv_cb);               // hold timer (to let hardware absorb the data
            end
            
//line 1 is brain( checking if it is safe to proceed)
//line 2 is muscle ( actually driving the data onto the wires ( it cant move unless it gets green light from the line 1)


            // Inject calculated tailing Parity check byte  (PARITY PHASE)
            while(vif.drv_cb.busy) @(vif.drv_cb);
            vif.drv_cb.pkt_valid <= 1'b0; // Lower valid to indicate parity transaction
            vif.drv_cb.datain    <= tx.computed_parity;
            @(vif.drv_cb);
            

            //CLEANUP AND HANDOFF PHASE
            vif.drv_cb.datain    <= 8'h00; // Idle out data lane
            repeat(2) @(vif.drv_cb); // Guard buffer spacing
            
            -> drv_done; // Release event lock back to Generator loop
        end
    endtask
endclass
