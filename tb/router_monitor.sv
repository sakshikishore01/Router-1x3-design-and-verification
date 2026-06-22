`timescale 1ns / 1ps

class monitor;
    virtual router_interface vif;
    mailbox mon2scb;

    // Constructor to connect the interface and scoreboard link
    function new(virtual router_interface vif, mailbox mon2scb);
        this.vif     = vif;
        this.mon2scb = mon2scb;
    endfunction

    // Main running task executing the transaction collection logic
    task run();
        router_transaction t;
        int active_ch; // Variable parameter to lock onto output lane (0, 1, or 2)
        
        forever begin
            @(vif.mon_cb); // Synchronize to the rising clock edge of the monitor clocking block

            // 1. Detect start of a packet cycle by monitoring valid output pins
            if(vif.mon_cb.vld_out_0 || vif.mon_cb.vld_out_1 || vif.mon_cb.vld_out_2) begin
                t = new();

                // Instantly record which channel triggered the transaction stream
                if(vif.mon_cb.vld_out_0)      active_ch = 0;
                else if(vif.mon_cb.vld_out_1) active_ch = 1;
                else                          active_ch = 2;

                // 2. Capture Header Byte and drive matching Read Enable through the clocking block
                case(active_ch)
                    0: begin t.header = vif.mon_cb.data_out_0; vif.mon_cb.read_enb_0 <= 1'b1; end
                    1: begin t.header = vif.mon_cb.data_out_1; vif.mon_cb.read_enb_1 <= 1'b1; end
                    2: begin t.header = vif.mon_cb.data_out_2; vif.mon_cb.read_enb_2 <= 1'b1; end
                endcase
                
                // Bit-slice the header parameters back to the transaction container fields
                t.destination_id = t.header[1:0];
                t.packet_length  = t.header[7:2];
                t.payload        = new[t.packet_length];
                
                @(vif.mon_cb); // Step forward to clear the latency delay of the FIFO

                // 3. Sequential loop to stream payload contents byte-by-byte
                for(int i = 0; i < t.packet_length; i++) begin
                    case(active_ch)
                        0: t.payload[i] = vif.mon_cb.data_out_0;
                        1: t.payload[i] = vif.mon_cb.data_out_1;
                        2: t.payload[i] = vif.mon_cb.data_out_2;
                    endcase
                    @(vif.mon_cb); // Wait for the next valid data cycle
                end

                // 4. Capture the trailing parity checksum byte from the wires
                case(active_ch)
                    0: t.computed_parity = vif.mon_cb.data_out_0;
                    1: t.computed_parity = vif.mon_cb.data_out_1;
                    2: t.computed_parity = vif.mon_cb.data_out_2;
                endcase
                
                // Also capture the protocol error state from the interface
                t.error = vif.mon_cb.error;

                // 5. Turn off the corresponding read enable to complete the readout phase
                case(active_ch)
                    0: vif.mon_cb.read_enb_0 <= 1'b0;
                    1: vif.mon_cb.read_enb_1 <= 1'b0;
                    2: vif.mon_cb.read_enb_2 <= 1'b0;
                endcase

                // Ship the fully reconstructed transaction object copy to the scoreboard mailbox
                mon2scb.put(t);
                $display("[MONITOR] Successfully parsed packet egress stream from Channel %0d to Scoreboard. Len: %0d", active_ch, t.packet_length);
            end
        end
    endtask
endclass
