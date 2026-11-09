// sparkle_linear.sv
// Purpose : SPARKLE512 linear diffusion layer L8 (SPARKLE spec Alg. 2.7).
//           tx = x0^x1^x2^x3, ty = y0^y1^y2^y3,
//           tx = rotl16(tx ^ (tx << 16)), same for ty (<< is a plain shift),
//           x(4+i) ^= x(i) ^ ty, y(4+i) ^= y(i) ^ tx for i = 0..3,
//           then branch permutation (x0..x7) <- (x5 x6 x7 x4 x0 x1 x2 x3),
//           same for y (x0..x3 are the original left words, x4..x7 updated).
// Ports   : state_in  [511:0] - input state
//           state_out [511:0] - output state
//           Bus convention: 16 words, word k at bits [32*k+31:32*k],
//           order x0 y0 x1 y1 ... x7 y7 (x_i = word 2i, y_i = word 2i+1).
// Latency : 0 cycles (purely combinational)
module sparkle_linear (
    input  logic [511:0] state_in,
    output logic [511:0] state_out
);

    // Unpack branch words
    logic [31:0] x [0:7];
    logic [31:0] y [0:7];
    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : g_unpack
            assign x[i] = state_in[64*i +: 32];
            assign y[i] = state_in[64*i+32 +: 32];
        end
    endgenerate

    // Feistel function: tx/ty
    logic [31:0] tx0, ty0, tx1, ty1, tx, ty;
    assign tx0 = x[0] ^ x[1] ^ x[2] ^ x[3];
    assign ty0 = y[0] ^ y[1] ^ y[2] ^ y[3];
    assign tx1 = tx0 ^ {tx0[15:0], 16'h0000};          // tx ^ (tx << 16)
    assign ty1 = ty0 ^ {ty0[15:0], 16'h0000};
    assign tx  = {tx1[15:0], tx1[31:16]};              // rotl16
    assign ty  = {ty1[15:0], ty1[31:16]};

    // Update right half, then permute
    logic [31:0] xr [0:3];
    logic [31:0] yr [0:3];
    generate
        for (i = 0; i < 4; i = i + 1) begin : g_mix
            assign xr[i] = x[4+i] ^ x[i] ^ ty;
            assign yr[i] = y[4+i] ^ y[i] ^ tx;
            // new branch 4+i = old left branch i
            assign state_out[64*(4+i) +: 32]    = x[i];
            assign state_out[64*(4+i)+32 +: 32] = y[i];
        end
    endgenerate

    // new branches 0..3 = updated right branches 5,6,7,4 (xr index 1,2,3,0)
    assign state_out[64*0 +: 32]    = xr[1];
    assign state_out[64*0+32 +: 32] = yr[1];
    assign state_out[64*1 +: 32]    = xr[2];
    assign state_out[64*1+32 +: 32] = yr[2];
    assign state_out[64*2 +: 32]    = xr[3];
    assign state_out[64*2+32 +: 32] = yr[3];
    assign state_out[64*3 +: 32]    = xr[0];
    assign state_out[64*3+32 +: 32] = yr[0];

endmodule
