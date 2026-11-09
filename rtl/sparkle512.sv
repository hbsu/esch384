// sparkle512.sv
// Purpose : Standalone iterative SPARKLE512 permutation, one step per
//           clock cycle (uses one combinational sparkle_step).
//           Slim = 8 steps, big = 12 steps.
// Ports   : clk, rst        - clock, synchronous active-high reset
//           start           - load state_in and begin (ignored while busy)
//           big             - 0: 8 steps, 1: 12 steps (sampled with start)
//           state_in [511:0]  - input state (sampled with start)
//           state_out [511:0] - state register; holds result after done
//           busy            - high while steps are being applied
//           done            - one-cycle pulse when the result is ready
//           Bus convention as in sparkle_linear.sv.
// Latency : start sampled at edge 0; steps applied at edges 1..N;
//           done is high in the cycle after edge N, i.e. N+1 cycles after
//           the start cycle (9 cycles slim, 13 cycles big).
module sparkle512 (
    input  logic         clk,
    input  logic         rst,
    input  logic         start,
    input  logic         big,
    input  logic [511:0] state_in,
    output logic [511:0] state_out,
    output logic         busy,
    output logic         done
);

    logic [511:0] state_reg;
    logic [511:0] step_out;
    logic [3:0]   cnt;
    logic [3:0]   last;   // index of the final step (7 or 11)

    sparkle_step u_step (
        .state_in  (state_reg),
        .step_idx  (cnt),
        .state_out (step_out)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            state_reg <= 512'd0;
            cnt       <= 4'd0;
            last      <= 4'd0;
            busy      <= 1'b0;
            done      <= 1'b0;
        end else begin
            done <= 1'b0;
            if (busy) begin
                state_reg <= step_out;
                cnt       <= cnt + 4'd1;
                if (cnt == last) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end
            end else if (start) begin
                state_reg <= state_in;
                cnt       <= 4'd0;
                last      <= big ? 4'd11 : 4'd7;
                busy      <= 1'b1;
            end
        end
    end

    assign state_out = state_reg;

endmodule
