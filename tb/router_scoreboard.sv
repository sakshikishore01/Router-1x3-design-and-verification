`timescale 1ns / 1ps

class scoreboard;
    mailbox mon2scb;
    mailbox gen2scb;

    int packets_verified = 0; 
    int error_count = 0;

    function new(mailbox mon2scb, mailbox gen2scb);
        this.mon2scb = mon2scb;
        this.gen2scb = gen2scb;
    endfunction

    task run();
        router_transaction exp, act;
        bit [7:0] calc_parity; // <-- FIXED: Variable declared here at the top!
        
        forever begin
            gen2scb.get(exp);
            mon2scb.get(act);

            // Now we just assign and recompute parity here
            calc_parity = act.header; 
            foreach(act.payload[i]) begin
                calc_parity ^= act.payload[i];
            end

            // 1. Destination Check
            if(exp.header[1:0] != act.header[1:0]) begin
                $error("FAIL: Dest mismatch Exp=%0b Act=%0b", 
                       exp.header[1:0], act.header[1:0]);
            end

            // 2. Parity Check and Error Signal Validation
            if(calc_parity == exp.computed_parity && act.error == 1'b0) begin
                $display("PASS: Parity matched, DUT correct");
            end 
            else if(calc_parity != exp.computed_parity && act.error == 1'b1) begin
                $display("PASS: DUT correctly flagged parity error");
            end 
            else begin
                $error("FAIL: DUT parity handling mismatch! Calc Parity=0x%0h, Exp Parity=0x%0h, DUT Error Bit=%0b", 
                       calc_parity, exp.computed_parity, act.error);
            end
        end
    endtask
endclass
