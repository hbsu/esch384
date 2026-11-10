// esch_ctrl.sv
// Purpose : Esch384 controller FSM. Runs the hash sequence on esch_datapath
//           and the valid/ready handshakes:
//             blocks 0..n-2 : inject -> 8 steps (idx 0..7)
//             block  n-1    : inject (final, ConstM) -> 12 steps (idx 0..11)
//             D0 -> 8 steps -> D1 -> 8 steps -> D2 (then clear the state)
//           Block data goes straight from the input bus to the datapath;
//           this module only makes the control signals.
// States  : WAIT (wait for a block), ABS (absorb steps, 8 or 12),
//           OUT (one digest chunk valid, chunk = 0/1/2), SQZ (8 squeeze steps)
// Ports   : clk, rst     - clock, synchronous active-high reset -> WAIT
//           in_valid     - sender has a block on the bus
//           in_ready     - 1 only in WAIT. Block accepted when
//                          in_valid && in_ready (that same cycle)
//           in_last      - the block on the bus is the final one
//           in_bytes[4:0]- bytes in the block (0..16). Not used here; the
//                          datapath reads it directly (kept for a complete
//                          input interface)
//           out_valid    - 1 only in OUT: datapath digest_chunk is D0/D1/D2
//           out_ready    - receiver takes the chunk when out_valid && out_ready
//           out_last     - 1 with out_valid on chunk D2
//           dp_clear     - 1 on the cycle D2 is accepted (state <= 0)
//           dp_inject    - = in_valid && in_ready (inject on that edge)
//           dp_step_en   - 1 in ABS and SQZ (one step per cycle)
//           dp_step_idx  - step number, 0..7 (slim) or 0..11 (big)
//           dp_msg_last  - = in_last (pass-through, used with dp_inject)
//           busy         - 1 from the cycle after the first block is accepted
//                          until (and including) the cycle D2 is accepted
// Latency : n blocks, no stalls, counted from the cycle the first block is
//           accepted (cycle 1) to the cycle D2 is accepted (inclusive):
//             9(n-1) + 13 + (1 + 8 + 1 + 8 + 1) = 9n + 23 cycles
//           (n = 1: 32 cycles). Each non-final block: 1 accept + 8 steps.
//           The next message's first block can be accepted 1 cycle after D2.
module esch_ctrl (
    input  logic       clk,
    input  logic       rst,
    input  logic       in_valid,
    output logic       in_ready,
    input  logic       in_last,
    input  logic [4:0] in_bytes,
    output logic       out_valid,
    input  logic       out_ready,
    output logic       out_last,
    output logic       dp_clear,
    output logic       dp_inject,
    output logic       dp_step_en,
    output logic [3:0] dp_step_idx,
    output logic       dp_msg_last,
    output logic       busy
);

    localparam logic [1:0] S_WAIT = 2'd0;
    localparam logic [1:0] S_ABS  = 2'd1;
    localparam logic [1:0] S_OUT  = 2'd2;
    localparam logic [1:0] S_SQZ  = 2'd3;

    logic [1:0] state;
    logic [3:0] cnt;      // step counter
    logic       big;      // current absorb is the final block (12 steps)
    logic [1:0] chunk;    // digest chunk number 0..2
    logic       in_msg;   // a non-final block was accepted, message not done

    logic accept;         // block accepted this cycle
    logic out_acc;        // digest chunk accepted this cycle
    logic last_step;      // this is the final step of ABS / SQZ

    assign accept    = in_valid && (state == S_WAIT);
    assign out_acc   = out_ready && (state == S_OUT);
    assign last_step = (state == S_ABS) ? (cnt == (big ? 4'd11 : 4'd7))
                                        : (cnt == 4'd7);

    // ---- Outputs (Moore, except dp_inject / dp_clear / dp_msg_last) ----
    assign in_ready    = (state == S_WAIT);
    assign dp_inject   = accept;
    assign dp_msg_last = in_last;
    assign dp_step_en  = (state == S_ABS) || (state == S_SQZ);
    assign dp_step_idx = cnt;
    assign out_valid   = (state == S_OUT);
    assign out_last    = (state == S_OUT) && (chunk == 2'd2);
    assign dp_clear    = out_acc && (chunk == 2'd2);
    assign busy        = (state != S_WAIT) || in_msg;

    // ---- State register ----
    always_ff @(posedge clk) begin
        if (rst) begin
            state  <= S_WAIT;
            cnt    <= 4'd0;
            big    <= 1'b0;
            chunk  <= 2'd0;
            in_msg <= 1'b0;
        end else begin
            case (state)
                S_WAIT: begin
                    if (accept) begin
                        state  <= S_ABS;
                        cnt    <= 4'd0;
                        big    <= in_last;
                        in_msg <= ~in_last;
                        chunk  <= 2'd0;
                    end
                end
                S_ABS: begin
                    cnt <= cnt + 4'd1;
                    if (last_step) begin
                        cnt   <= 4'd0;
                        state <= big ? S_OUT : S_WAIT;
                    end
                end
                S_OUT: begin
                    if (out_acc) begin
                        cnt <= 4'd0;
                        if (chunk == 2'd2) begin
                            state <= S_WAIT;
                            chunk <= 2'd0;
                        end else begin
                            state <= S_SQZ;
                            chunk <= chunk + 2'd1;
                        end
                    end
                end
                default: begin  // S_SQZ
                    cnt <= cnt + 4'd1;
                    if (last_step) begin
                        cnt   <= 4'd0;
                        state <= S_OUT;
                    end
                end
            endcase
        end
    end

endmodule
