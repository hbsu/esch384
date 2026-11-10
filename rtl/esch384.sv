// esch384.sv
// Purpose : Esch384 hash, top level. Wires the controller FSM (esch_ctrl)
//           to the datapath (esch_datapath). Message blocks go straight from
//           the input bus into the datapath; the digest leaves as three
//           128-bit chunks D0, D1, D2. After D2 is accepted the state is
//           cleared, so the next message can follow with no reset.
// Ports   : clk, rst      - clock, synchronous active-high reset
//           in_valid      - sender has a block on in_data
//           in_ready      - 1 when a block can be accepted; a block is
//                           taken when in_valid && in_ready (same cycle)
//           in_last       - this block is the final block of the message
//           in_bytes[4:0] - valid bytes in the block, 0..16
//                           (0 only for the empty message, with in_last=1;
//                           non-final blocks must have 16)
//           in_data[127:0]- block, message byte k at bits [8k+7:8k];
//                           bytes >= in_bytes are ignored (padded inside)
//           out_valid     - out_data holds a digest chunk
//           out_ready     - receiver takes the chunk when out_valid && out_ready
//           out_last      - 1 with chunk D2
//           out_data[127:0] - D0, D1, D2 in order; digest byte 16j+k is at
//                           bits [8k+7:8k] of chunk Dj (little-endian)
//           busy          - 1 while a message is in progress
// Latency : n blocks (n = 1 for the empty message), no stalls, from the cycle
//           the first block is accepted to the cycle D2 is accepted,
//           inclusive: 9n + 23 cycles (32 for one block).
// Throughput: one step per clock; 16 bytes per 9 cycles for long messages
//           (each extra block: 1 accept cycle + 8 steps). The next message's
//           first block can be accepted the cycle after D2.
module esch384 (
    input  logic         clk,
    input  logic         rst,
    input  logic         in_valid,
    output logic         in_ready,
    input  logic         in_last,
    input  logic [4:0]   in_bytes,
    input  logic [127:0] in_data,
    output logic         out_valid,
    input  logic         out_ready,
    output logic         out_last,
    output logic [127:0] out_data,
    output logic         busy
);

    logic         dp_clear, dp_inject, dp_step_en, dp_msg_last;
    logic [3:0]   dp_step_idx;
    logic [511:0] dp_state;

    esch_ctrl u_ctrl (
        .clk         (clk),
        .rst         (rst),
        .in_valid    (in_valid),
        .in_ready    (in_ready),
        .in_last     (in_last),
        .in_bytes    (in_bytes),
        .out_valid   (out_valid),
        .out_ready   (out_ready),
        .out_last    (out_last),
        .dp_clear    (dp_clear),
        .dp_inject   (dp_inject),
        .dp_step_en  (dp_step_en),
        .dp_step_idx (dp_step_idx),
        .dp_msg_last (dp_msg_last),
        .busy        (busy)
    );

    esch_datapath u_dp (
        .clk          (clk),
        .rst          (rst),
        .clear        (dp_clear),
        .inject       (dp_inject),
        .step_en      (dp_step_en),
        .step_idx     (dp_step_idx),
        .msg_block    (in_data),
        .msg_bytes    (in_bytes),
        .msg_last     (dp_msg_last),
        .state_out    (dp_state),
        .digest_chunk (out_data)
    );

endmodule
