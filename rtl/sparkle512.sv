// sparkle512.sv
// Purpose : Standalone iterative SPARKLE512 permutation.
//           Slim = 8 steps, big = 12 steps.
//           Parameter NALZ sets how many Alzette ARX-boxes are built:
//             NALZ = 8 : one full step per cycle (one sparkle_step).
//             NALZ = 4, 2, 1 : the Alzettes are shared. A step takes
//               NSUB = 8/NALZ cycles. Each cycle, the NALZ lowest branches
//               of the state go through the Alzettes and the whole state
//               shifts down by NALZ branches (processed branches go to the
//               top). After NSUB cycles every branch is done and back in
//               its own place; the linear layer is applied in that last
//               cycle. The step constants (y0 ^= c[s mod 8], y1 ^= s) are
//               added in the first cycle of each step.
// Ports   : clk, rst        - clock, synchronous active-high reset
//           start           - load state_in and begin (ignored while busy)
//           big             - 0: 8 steps, 1: 12 steps (sampled with start)
//           state_in [511:0]  - input state (sampled with start)
//           state_out [511:0] - state register; holds result after done
//                               (mid-step values are partly shifted)
//           busy            - high while steps are being applied
//           done            - one-cycle pulse when the result is ready
//           Bus convention as in sparkle_linear.sv.
// Latency : start sampled at edge 0; NSUB cycles per step; done is high
//           steps*NSUB + 1 cycles after the start cycle:
//             NALZ = 8 :  9 slim, 13 big
//             NALZ = 4 : 17 slim, 25 big
//             NALZ = 2 : 33 slim, 49 big
//             NALZ = 1 : 65 slim, 97 big
module sparkle512 #(
    parameter integer NALZ = 8      // Alzette instances: 8, 4, 2 or 1
) (
    input  logic         clk,
    input  logic         rst,
    input  logic         start,
    input  logic         big,
    input  logic [511:0] state_in,
    output logic [511:0] state_out,
    output logic         busy,
    output logic         done
);

    localparam integer NSUB = 8 / NALZ;   // cycles per step

    logic [511:0] state_reg;
    logic [511:0] next_state;   // state after this cycle's work
    logic [3:0]   cnt;          // step number s
    logic [3:0]   last;         // index of the final step (7 or 11)
    logic [2:0]   sub;          // cycle within the step, 0..NSUB-1
    logic         step_end;     // this cycle finishes a step

    assign step_end = busy && (sub == NSUB - 1);

    generate
        if (NALZ == 8) begin : g_full
            // One whole step per cycle (original design)
            sparkle_step u_step (
                .state_in  (state_reg),
                .step_idx  (cnt),
                .state_out (next_state)
            );
        end else begin : g_shared
            // Round constants c0..c7, packed c0 in bits [31:0]
            // (same values as sparkle_step.sv)
            localparam logic [255:0] RCON = {
                32'hC2B3293D, 32'hCFBFA1C8, 32'h4F7C7B57, 32'hBB1185EB,
                32'h324E7738, 32'h38B4DA56, 32'hBF715880, 32'hB7E15162
            };

            logic [511:0]        pre;     // state with step constants added
            logic [64*NALZ-1:0]  arx;     // Alzette outputs, NALZ branches
            logic [511:0]        rot;     // state shifted down by NALZ branches
            logic [511:0]        lin_out; // rot after the linear layer

            // Step constants, only in the first cycle of a step (all
            // branches are in their own place then)
            always_comb begin
                pre = state_reg;
                if (sub == 3'd0) begin
                    pre[63:32]  = state_reg[63:32]  ^ RCON[32*cnt[2:0] +: 32]; // y0
                    pre[127:96] = state_reg[127:96] ^ {28'd0, cnt};           // y1
                end
            end

            // NALZ Alzettes on the lowest branches. Position i holds
            // branch sub*NALZ + i, which uses constant c[sub*NALZ + i].
            genvar i;
            for (i = 0; i < NALZ; i = i + 1) begin : g_alz
                logic [31:0] c_i;
                assign c_i = RCON[32*(sub*NALZ + i) +: 32];
                alzette u_alz (
                    .x_in  (pre[64*i +: 32]),
                    .y_in  (pre[64*i+32 +: 32]),
                    .c     (c_i),
                    .x_out (arx[64*i +: 32]),
                    .y_out (arx[64*i+32 +: 32])
                );
            end

            // Shift down; processed branches go on top
            assign rot = {arx, pre[511:64*NALZ]};

            sparkle_linear u_lin (
                .state_in  (rot),
                .state_out (lin_out)
            );

            assign next_state = (sub == NSUB - 1) ? lin_out : rot;
        end
    endgenerate

    always_ff @(posedge clk) begin
        if (rst) begin
            state_reg <= 512'd0;
            cnt       <= 4'd0;
            last      <= 4'd0;
            sub       <= 3'd0;
            busy      <= 1'b0;
            done      <= 1'b0;
        end else begin
            done <= 1'b0;
            if (busy) begin
                state_reg <= next_state;
                if (step_end) begin
                    sub <= 3'd0;
                    cnt <= cnt + 4'd1;
                    if (cnt == last) begin
                        busy <= 1'b0;
                        done <= 1'b1;
                    end
                end else begin
                    sub <= sub + 3'd1;
                end
            end else if (start) begin
                state_reg <= state_in;
                cnt       <= 4'd0;
                sub       <= 3'd0;
                last      <= big ? 4'd11 : 4'd7;
                busy      <= 1'b1;
            end
        end
    end

    assign state_out = state_reg;

endmodule
