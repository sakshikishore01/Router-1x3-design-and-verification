`timescale 1ns / 1ps

class router_transaction;
    // Randomized Inputs matching your router specifications
    rand bit [1:0] destination_id;
    rand bit [5:0] packet_length;
    rand bit [7:0] payload[];
    
    // Non-randomized validation fields
         bit [7:0] header;
         bit [7:0] computed_parity;
         bit [7:0] error;

    // Constraints to ensure realistic network traffic
    constraint valid_dest { destination_id inside {2'b00, 2'b01, 2'b10}; }
    constraint valid_len  { packet_length inside {[1:30]}; } // Avoid FIFO overflows during standard verification
    constraint payload_size { payload.size() == packet_length; }

    // Automatically calculates internal parity byte for the transaction object
    function void post_randomize();
        header = {packet_length, destination_id};
        computed_parity = header;
        foreach (payload[i]) begin
            computed_parity = computed_parity ^ payload[i];
        end
    endfunction

    // Deep copy utility method
    function router_transaction copy();
        copy = new();
        copy.destination_id = this.destination_id;
        copy.packet_length  = this.packet_length;
        copy.payload        = new[this.payload.size()](this.payload);
        copy.header         = this.header;
        copy.computed_parity= this.computed_parity;
        return copy;
    endfunction
endclass
