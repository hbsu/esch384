// esch_inject.sv

// Purpose : Pads the final block if short, then XORs one 16-byte message
//           block (and the final-block constant) into the state (Alg. 2.10).
// Ports   : state_in  [511:0] - state before injection
//           blk_data  [127:0] - message block, byte i at [8i+7:8i]
//           blk_bytes [4:0]   - valid bytes, 0-16 (only used when blk_last =1)
//           blk_last          - final block; pad if short, add the constant
//           state_out [511:0] - state after injection
// Latency : 0 cycles (purely combinational)

module esch_inject (
    
    input  logic [511:0] state_in,
    input  logic [127:0] blk_data,
    input  logic [4:0]   blk_bytes,
    input  logic         blk_last,
    output logic [511:0] state_out

);

logic [31:0] m0, m1, m2, m3, a, b, tx, ty, x0, x1, x2, x3, y0, y1, y2, y3, cm;

logic [127:0] padded;       // Input Array
integer i;                  // Loop Increment Value


always_comb begin
    for(i = 0; i < 16; i = i + 1) begin

        // If the current block is not the last block or last available byte copy in to the padded array
        if (!blk_last || i < blk_bytes)
            padded[8 * i +: 8] = blk_data[8 * i +: 8];

        // If its the last available block then copy x80 into its location in padded array
        else if (i == blk_bytes)
            padded[8 * i +: 8] = 8'h80;

        // Any remaining locations corresponding to after the last available input byte should be x00
        else
            padded[8 * i +: 8] = 8'h00;
    end
end

// Create the four sub-blocks from the initial input block
assign m0 = padded[31:0];
assign m1 = padded[63:32];
assign m2 = padded[95:64];
assign m3 = padded[127:96];

// Create two new derived blocks tx and ty
assign a = m0 ^ m2;
assign b = m1 ^ m3;

assign tx = {a[15:0], a[31:16] ^ a[15:0]};
assign ty = {b[15:0], b[31:16] ^ b[15:0]};

// Constant M depends on the block type and characteristics if it is the last block
assign cm = !blk_last            ? 32'h00000000 : // Not the last block; more coming
            (blk_bytes == 5'd16) ? 32'h02000000 : // Ended on a full block
                                   32'h01000000;  // Ended on a padded block

// Finally, we will create the eight 32 bit words to disperse across the LSB of the internal state
assign x0 = m0 ^ ty;
assign y0 = m1 ^ tx;
assign x1 = m2 ^ ty;
assign y1 = m3 ^ tx;
assign x2 = ty;
assign y2 = tx;
assign x3 = ty;
assign y3 = tx ^ cm;

// XOR the pieces we just derrived with the least significant half of the output state
assign state_out = state_in ^{256'd0,y3, x3, y2, x2, y1, x1, y0, x0};


endmodule

