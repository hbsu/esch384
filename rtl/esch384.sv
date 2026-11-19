// esch384.sv
//
// Purpose : Top level Esch384 hash. Wires the datapath (state register,
//           injection, permutation) to the controller FSM. Takes the
//           message one 16-byte block at a time and gives the 48-byte
//           digest back as three 128-bit chunks, D0 then D1 then D2.
// Ports   : clk and rst for clock and reset
//           blk_data  [127:0] message block, byte i at bits [8i+7:8i]
//           blk_bytes [4:0]   valid bytes in this block, 0-16; only read
//                             on the last block (non-last blocks are full)
//           in_last           this block is the last one of the message
//           in_valid          the sender has a block ready
//           in_ready          the core takes a block this cycle; a block
//                             moves only when in_valid and in_ready are
//                             both high at a rising edge
//           digest_chunk [127:0] one 128-bit piece of the digest, bytes
//                             little-endian (byte 0 at bits [7:0])
//           out_valid         digest_chunk holds D0, D1, or D2 now
//           out_ready         the receiver takes the chunk this cycle
// Notes   : An empty message is one block with blk_bytes = 0 and
//           in_last = 1. After D2 is taken the core resets itself and is
//           ready for a new message.
// Params  : NALZ = number of Alzette ARX-boxes (8, 4, 2 or 1). Fewer
//           Alzettes = less area, NSUB = 8/NALZ cycles per step.
// Latency : 8n + 20 permutation steps for an n-block message. With a
//           sender and receiver that never stall,
//           (8*NSUB + 2)*n + 20*NSUB + 4 cycles from the cycle the first
//           block is taken to the cycle D2 is taken.
//           NALZ = 8: 10n + 24 (34 cycles for a one-block message).

module esch384 #(
    parameter integer NALZ = 8
) (
    input  logic         clk,
    input  logic         rst,
    input  logic [127:0] blk_data,
    input  logic [4:0]   blk_bytes,
    input  logic         in_last,
    input  logic         in_valid,
    output logic         in_ready,
    output logic [127:0] digest_chunk,
    output logic         out_valid,
    input  logic         out_ready
);

    // Control lines between the FSM and the datapath
    logic first;        // inject into a zero state (new message)
    logic do_inject;    // one-cycle pulse: inject this block, then permute
    logic do_squeeze;   // one-cycle pulse: permute with no injection
    logic perm_busy;    // the permutation is running
    logic perm_done;    // one-cycle pulse: the permutation finished

    esch384_ctrl u_ctrl (
        .clk        (clk),
        .rst        (rst),
        .in_valid   (in_valid),
        .in_last    (in_last),
        .in_ready   (in_ready),
        .out_valid  (out_valid),
        .out_ready  (out_ready),
        .first      (first),
        .do_inject  (do_inject),
        .do_squeeze (do_squeeze),
        .perm_done  (perm_done)
    );

    esch384_datapath #(.NALZ(NALZ)) u_dp (
        .clk          (clk),
        .rst          (rst),
        .blk_data     (blk_data),
        .blk_bytes    (blk_bytes),
        .blk_last     (in_last),
        .first        (first),
        .do_inject    (do_inject),
        .do_squeeze   (do_squeeze),
        .perm_busy    (perm_busy),
        .perm_done    (perm_done),
        .digest_chunk (digest_chunk)
    );

endmodule
