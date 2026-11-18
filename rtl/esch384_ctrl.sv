// esch384_ctrl.sv
//
// Purpose : Controller FSM for Esch384. Decides when the datapath injects a
//           block, when it runs a squeeze permutation, and when a digest
//           chunk is ready. Does not see the message data itself.
// Ports   : clk and rst for clock and reset
//           in_valid   tells the controller that the sender has a block ready
//           in_last    tells the controller that the current block is the last one
//           in_ready   tells the sender that the controller can take the block this cycle
//           out_valid  tells the receiver that digest_chunk holds D0, D1, or D2 right now
//           out_ready  tells the controller that the receiver took it
//           first      tells the datapath to inject into a zero state (new hash)
//           do_inject  one-cycle pulse: inject the block and start the permutation
//           do_squeeze one-cycle pulse: start a slim permutation with no injection
//           perm_done  one-cycle pulse from the datapath: permutation finished
// States  : S_ABSORB (wait for a block), S_PERM_A (permute after a block),
//           S_OUT (show a digest chunk), S_PERM_S (permute between chunks)
// Latency : 8n + 20 permutation steps for n blocks, plus a few cycles per
//           phase (TBD, measured in task 6)

module esch384_ctrl (
    input  logic clk, rst,
    input  logic in_valid,
    input  logic in_last,
    output logic in_ready,
    output logic out_valid,
    input  logic out_ready,
    output logic first,
    output logic do_inject,
    output logic do_squeeze,
    input  logic perm_done
);

localparam [1:0] S_ABSORB = 2'd0, S_PERM_A = 2'd1, S_OUT = 2'd2, S_PERM_S = 2'd3;

logic [1:0]   state;
logic         first_r, last_seen;
logic [1:0]   chunk;              // which digest chunk is showing: 0, 1, 2

// 1. Outputs: instant logic from the current state + inputs
assign in_ready   = (state == S_ABSORB);                              // Currently waiting for a block
assign do_inject  = (state == S_ABSORB) && in_valid;                  // A block arrived so we should inject now
assign out_valid  = (state == S_OUT);                                 // A digest chunk is ready
assign do_squeeze = (state == S_OUT) && out_ready && (chunk != 2'd2); // The chunk was taken, now permute
assign first      = first_r;

// 2. Registers: one always_ff, follows the state table
always_ff @(posedge clk) begin
    if (rst) begin
        state     <= S_ABSORB;
        first_r   <= 1'b1;
        last_seen <= 1'b0;
        chunk     <= 2'd0;
    end else begin
        case (state)

            // Wait for a block from the sender
            S_ABSORB: begin
                if (in_valid) begin
                    last_seen <= in_last;
                    first_r   <= 1'b0;
                    state     <= S_PERM_A;
                end
            end

            // Wait for the permutation after a block
            S_PERM_A: begin
                if (perm_done) begin
                    if (last_seen) begin
                        chunk <= 2'd0;
                        state <= S_OUT;
                    end else begin
                        state <= S_ABSORB;
                    end
                end
            end

            // Show a digest chunk, wait for the receiver to take it
            S_OUT: begin
                if (out_ready) begin
                    if (chunk != 2'd2) begin
                        chunk <= chunk + 2'd1;
                        state <= S_PERM_S;
                    end else begin
                        first_r <= 1'b1;
                        state   <= S_ABSORB;
                    end
                end
            end

            // Wait for the permutation between chunks
            S_PERM_S: begin
                if (perm_done) begin
                    state <= S_OUT;
                end
            end

            default: state <= S_ABSORB;
        endcase
    end
end

endmodule
