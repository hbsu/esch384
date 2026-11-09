// sparkle_step.sv
// Purpose : One SPARKLE512 step (SPARKLE spec Alg. 2.3, one loop pass):
//           y0 ^= c[s mod 8], y1 ^= s, Alzette on all 8 branches with
//           constant c[i], then linear layer L8 (sparkle_linear).
// Ports   : state_in  [511:0] - state before the step
//           step_idx  [3:0]   - step number s (0..11)
//           state_out [511:0] - state after the step
//           Bus convention as in sparkle_linear.sv: word k at
//           bits [32*k+31:32*k], order x0 y0 x1 y1 ... x7 y7.
// Latency : 0 cycles (purely combinational)
module sparkle_step (
    input  logic [511:0] state_in,
    input  logic [3:0]   step_idx,
    output logic [511:0] state_out
);

    // Round constants c0..c7, packed c0 in bits [31:0]
    localparam logic [255:0] RCON = {
        32'hC2B3293D, 32'hCFBFA1C8, 32'h4F7C7B57, 32'hBB1185EB,
        32'h324E7738, 32'h38B4DA56, 32'hBF715880, 32'hB7E15162
    };

    // Step constant injection: y0 ^= c[s mod 8], y1 ^= s
    logic [31:0]  step_c;
    logic [511:0] injected;
    assign step_c = RCON[32*step_idx[2:0] +: 32];

    assign injected[31:0]    = state_in[31:0];                       // x0
    assign injected[63:32]   = state_in[63:32] ^ step_c;             // y0
    assign injected[95:64]   = state_in[95:64];                      // x1
    assign injected[127:96]  = state_in[127:96] ^ {28'd0, step_idx}; // y1
    assign injected[511:128] = state_in[511:128];

    // Alzette layer: branch i uses constant c[i]
    logic [511:0] arx;
    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : g_alz
            alzette u_alz (
                .x_in  (injected[64*i +: 32]),
                .y_in  (injected[64*i+32 +: 32]),
                .c     (RCON[32*i +: 32]),
                .x_out (arx[64*i +: 32]),
                .y_out (arx[64*i+32 +: 32])
            );
        end
    endgenerate

    // Linear diffusion layer
    sparkle_linear u_lin (
        .state_in  (arx),
        .state_out (state_out)
    );

endmodule
