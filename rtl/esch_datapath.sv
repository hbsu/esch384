// esch_datapath.sv
// Purpose : Esch384 datapath: 512-bit state register, message padding and
//           injection (Feistel M4 of the 128-bit block, SPARKLE spec
//           Alg. 2.10), final-block constant ConstM, one SPARKLE512 step
//           per clock (sparkle_step), and digest output select.
//           A controller drives the control inputs (task 5).
// Ports   : clk           - clock
//           rst           - synchronous active-high reset: state <= 0
//           clear         - state <= 0
//           inject        - state <= state ^ injection(padded msg_block)
//                           (plus ConstM into y3 when msg_last = 1)
//           step_en       - state <= sparkle_step(state, step_idx)
//           step_idx[3:0] - step number s (0..7 slim, 0..11 big)
//           msg_block[127:0] - message block, byte k at bits [8k+7:8k]
//                           (little-endian, same as the state bus)
//           msg_bytes[4:0]- valid bytes in msg_block, 0..16. If < 16 the
//                           block is padded: byte msg_bytes = 0x80, later
//                           bytes = 0 (input bytes >= msg_bytes are ignored).
//                           Values > 16 are treated as 16 (full block).
//           msg_last      - final block: also XOR ConstM into y3:
//                           0x01000000 if padded (msg_bytes < 16),
//                           0x02000000 if full (hash.c CONST_M1 / CONST_M2)
//           state_out[511:0]   - the state register; word k at bits
//                           [32k+31:32k], order x0 y0 x1 y1 ... x7 y7
//           digest_chunk[127:0] - state_out[127:0] = x0 y0 x1 y1, i.e.
//                           16 digest bytes, byte k at bits [8k+7:8k]
// Priority: rst > clear > inject > step_en; all low = hold state.
// Latency : 1 clock per action (result visible after the clock edge).
//           digest_chunk is combinational from the state register.
module esch_datapath (
    input  logic         clk,
    input  logic         rst,
    input  logic         clear,
    input  logic         inject,
    input  logic         step_en,
    input  logic [3:0]   step_idx,
    input  logic [127:0] msg_block,
    input  logic [4:0]   msg_bytes,
    input  logic         msg_last,
    output logic [511:0] state_out,
    output logic [127:0] digest_chunk
);

    localparam logic [31:0] CONST_M1 = 32'h01000000;  // final block, padded
    localparam logic [31:0] CONST_M2 = 32'h02000000;  // final block, full

    logic [511:0] state_reg;
    logic [511:0] step_out;
    logic [511:0] inj_state;
    logic [127:0] pad_blk;
    logic         padded;
    logic [31:0]  m0, m1, m2, m3;
    logic [31:0]  ux, uy, tx, ty;
    logic [31:0]  const_m;

    // ---- Padding: keep bytes < msg_bytes, 0x80 at msg_bytes, zeros after ----
    genvar k;
    generate
        for (k = 0; k < 16; k = k + 1) begin : g_pad
            assign pad_blk[8*k +: 8] =
                (k < msg_bytes)  ? msg_block[8*k +: 8] :
                (k == msg_bytes) ? 8'h80 : 8'h00;
        end
    endgenerate

    assign padded = (msg_bytes < 5'd16);

    assign m0 = pad_blk[31:0];
    assign m1 = pad_blk[63:32];
    assign m2 = pad_blk[95:64];
    assign m3 = pad_blk[127:96];

    // ---- Feistel injection: l(t) = rotl16(t ^ (t << 16)) ----
    assign ux = (m0 ^ m2) ^ {(m0[15:0] ^ m2[15:0]), 16'h0000};
    assign uy = (m1 ^ m3) ^ {(m1[15:0] ^ m3[15:0]), 16'h0000};
    assign tx = {ux[15:0], ux[31:16]};
    assign ty = {uy[15:0], uy[31:16]};

    assign const_m = msg_last ? (padded ? CONST_M1 : CONST_M2) : 32'h00000000;

    assign inj_state[31:0]    = state_reg[31:0]    ^ m0 ^ ty;            // x0
    assign inj_state[63:32]   = state_reg[63:32]   ^ m1 ^ tx;            // y0
    assign inj_state[95:64]   = state_reg[95:64]   ^ m2 ^ ty;            // x1
    assign inj_state[127:96]  = state_reg[127:96]  ^ m3 ^ tx;            // y1
    assign inj_state[159:128] = state_reg[159:128] ^ ty;                 // x2
    assign inj_state[191:160] = state_reg[191:160] ^ tx;                 // y2
    assign inj_state[223:192] = state_reg[223:192] ^ ty;                 // x3
    assign inj_state[255:224] = state_reg[255:224] ^ tx ^ const_m;       // y3
    assign inj_state[511:256] = state_reg[511:256];                      // x4..y7

    // ---- One SPARKLE512 step ----
    sparkle_step u_step (
        .state_in  (state_reg),
        .step_idx  (step_idx),
        .state_out (step_out)
    );

    // ---- State register ----
    always_ff @(posedge clk) begin
        if (rst)
            state_reg <= 512'd0;
        else if (clear)
            state_reg <= 512'd0;
        else if (inject)
            state_reg <= inj_state;
        else if (step_en)
            state_reg <= step_out;
    end

    assign state_out    = state_reg;
    assign digest_chunk = state_reg[127:0];

endmodule
