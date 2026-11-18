// esch384_datapath.sv
// 
// Purpose : Combines the esch injection with the sparkle permutation and selects between them 
//           Contains a clk and reset, facillitates control by linking the two modules
// Ports   : clk and rst for clock and reset
//           blk_data [127:0] is the incoming message 
//           blk_bytes [4:0] is the number of bytes in the message that are valid
//           blk last is a flag indicating the current block is the last one
//           first indicates that the current block is the the first in a new sequence
//           do_inject is a one cycle pulse that indicates to inject blk_data into the state and begin permutation
//           do_squeeze is a one cycle pulse that initiates a slim permutation on the state as is without injection
//           perm_busy asserts while sparkle is permuting so that we know not to pulse do_inject or do_squeeze
//           perm_done is a one cycle pulse that goes high when the permutation is complete and the state is ready for injection
//           digest_chunk always shows state_out[127:0] (x0, y0, x1, y1)
// Latency : sparkle512 is 9 cycles slim and 13 cycles big from the do_inject or do_squeeze cycle to perm_done

module esch384_datapath (
    
    input  logic clk, rst,
    input  logic [127:0] blk_data,
    input  logic [4:0]   blk_bytes,
    input  logic         blk_last, first, do_inject, do_squeeze,
    output logic         perm_busy, perm_done,
    output logic [127:0] digest_chunk

);

logic [511:0] perm_state;   // sparkle512's state_out
logic [511:0] cur;          // state to inject into
logic [511:0] injected;     // esch_inject's output

// The state after the recursive permutation has completed
// Feeds back into esch's initial state
assign cur = first ? 512'd0 : perm_state;

// Takes message block and state (either starting or previous)
 esch_inject esch_injection (
    
    .state_in  (cur),
    .blk_data  (blk_data),
    .blk_bytes (blk_bytes),
    .blk_last  (blk_last),
    .state_out (injected)

);

// Takes a state from esch and does either 8 or 12 permutation steps, returning the digest
 sparkle512 u_perm (
    .clk       (clk), .rst(rst),
    .start     (do_inject | do_squeeze),
    .big       (do_inject & blk_last),
    .state_in  (do_inject ? injected : perm_state),
    .state_out (perm_state),
    .busy      (perm_busy),
    .done      (perm_done)
);

// Output the rate: x0 y0 x1 y1
assign digest_chunk = perm_state[127:0];

endmodule
