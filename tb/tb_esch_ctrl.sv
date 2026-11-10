// tb_esch_ctrl.sv
// Self-checking testbench for esch_ctrl (controller only, no datapath).
// Inputs change on negedge. A monitor samples every control output at each
// posedge and follows the expected sequence per message:
//   WAIT -> (inject) 8 steps idx 0..7 -> WAIT ... -> (inject, last)
//   12 steps idx 0..11 -> D0 -> 8 steps -> D1 -> 8 steps -> D2 (+dp_clear)
// Every cycle it checks: in_ready/out_valid never both high, no step while
// in_ready or out_valid, dp_inject == in_valid && in_ready,
// dp_msg_last == in_last, busy, and the phase-specific outputs.
// Per message: injects == blocks sent, steps == 8n+20, one dp_clear,
// cycles (first accept .. D2 accept) == 9n+23 when there are no stalls.
// Tests: n = 1,2,3,5 back-to-back without stalls; the same with random
// sender/receiver stalls (fixed seed); reset mid-absorb and mid-output.
// Prints TEST PASSED (N/N) or TEST FAILED (k errors of N).
`timescale 1ns/1ps
module tb_esch_ctrl;
    logic       clk, rst;
    logic       in_valid, in_ready, in_last;
    logic [4:0] in_bytes;
    logic       out_valid, out_ready, out_last;
    logic       dp_clear, dp_inject, dp_step_en, dp_msg_last, busy;
    logic [3:0] dp_step_idx;

    esch_ctrl dut (.clk(clk), .rst(rst),
                   .in_valid(in_valid), .in_ready(in_ready), .in_last(in_last),
                   .in_bytes(in_bytes),
                   .out_valid(out_valid), .out_ready(out_ready), .out_last(out_last),
                   .dp_clear(dp_clear), .dp_inject(dp_inject), .dp_step_en(dp_step_en),
                   .dp_step_idx(dp_step_idx), .dp_msg_last(dp_msg_last), .busy(busy));

    initial clk = 0;
    always #5 clk = ~clk;

    integer nchk, errs;
    integer seed;

    task automatic chk(input logic ok, input string what);
        nchk = nchk + 1;
        if (!ok) begin
            errs = errs + 1;
            if (errs <= 30) $display("ERROR t=%0t: %s", $time, what);
        end
    endtask

    // ---- Test plan ----
    localparam integer NMSG = 10;
    integer plan_n      [0:NMSG-1];
    integer plan_install[0:NMSG-1];
    integer plan_ostall [0:NMSG-1];
    initial begin
        plan_n[0] = 1; plan_n[1] = 2; plan_n[2] = 3; plan_n[3] = 5; plan_n[4] = 1;
        plan_n[5] = 1; plan_n[6] = 2; plan_n[7] = 3; plan_n[8] = 5; plan_n[9] = 3;
        for (int i = 0; i < NMSG; i++) begin
            plan_install[i] = (i >= 5);
            plan_ostall[i]  = (i >= 5);
        end
        plan_install[9] = 0;   // receiver-only stalls
        plan_ostall[8]  = 0;   // sender-only stalls
    end

    // ---- Monitor ----
    localparam integer M_WAIT = 0, M_ABS = 1, M_OUT = 2, M_SQZ = 3;
    integer mph;          // expected phase
    integer e_idx, e_max; // expected next step idx, last idx
    logic   m_last;       // current absorb is final
    integer m_chunk;
    logic   m_inmsg;      // between blocks of a message
    integer m_msg;        // messages completed (index of current)
    integer m_blocks, m_steps, m_clears, m_t0, cyc;
    integer m_ostall_cyc; // cycles with out_valid && !out_ready
    integer mon_en;       // 1 = check messages against the plan
    integer nstall_in, nstall_out;
    integer m_done_n [0:NMSG-1];
    string  s;

    task automatic mon_reset();
        mph = M_WAIT; e_idx = 0; e_max = 7; m_last = 0; m_chunk = 0;
        m_inmsg = 0; m_blocks = 0; m_steps = 0; m_clears = 0; m_t0 = 0;
        m_ostall_cyc = 0;
    endtask

    initial begin
        cyc = 0; m_msg = 0; mon_en = 1; nstall_out = 0;
        mon_reset();
    end

    always @(posedge clk) begin
        cyc = cyc + 1;
        if (rst) begin
            mon_reset();
        end else begin
            // every-cycle checks
            chk(!(in_ready && out_valid), "in_ready and out_valid both high");
            chk(!(dp_step_en && (in_ready || out_valid)), "step_en while in_ready/out_valid");
            chk(dp_inject === (in_valid && in_ready), "dp_inject != in_valid && in_ready");
            chk(dp_msg_last === in_last, "dp_msg_last != in_last");
            if (dp_step_en) m_steps = m_steps + 1;
            if (dp_clear)   m_clears = m_clears + 1;
            if (out_valid && !out_ready) nstall_out = nstall_out + 1;
            case (mph)
                M_WAIT: begin
                    chk(in_ready === 1'b1, "WAIT: in_ready low");
                    chk(out_valid === 1'b0 && dp_step_en === 1'b0 && dp_clear === 1'b0,
                        "WAIT: out_valid/step_en/clear high");
                    chk(busy === m_inmsg, "WAIT: busy wrong");
                    if (in_valid) begin
                        if (m_blocks == 0) m_t0 = cyc;
                        m_blocks = m_blocks + 1;
                        m_last = in_last;
                        e_idx = 0; e_max = in_last ? 11 : 7;
                        mph = M_ABS;
                    end
                end
                M_ABS, M_SQZ: begin
                    $sformat(s, "%s: step idx exp %0d got %0d (en=%b)",
                             (mph == M_ABS) ? "ABS" : "SQZ", e_idx, dp_step_idx, dp_step_en);
                    chk(dp_step_en === 1'b1 && dp_step_idx === e_idx[3:0], s);
                    chk(in_ready === 1'b0 && out_valid === 1'b0 && dp_clear === 1'b0,
                        "step phase: in_ready/out_valid/clear high");
                    chk(busy === 1'b1, "step phase: busy low");
                    e_idx = e_idx + 1;
                    if (e_idx > e_max) begin
                        if (mph == M_SQZ)      mph = M_OUT;
                        else if (m_last)       begin mph = M_OUT; m_chunk = 0; m_inmsg = 0; end
                        else                   begin mph = M_WAIT; m_inmsg = 1; end
                    end
                end
                M_OUT: begin
                    $sformat(s, "OUT D%0d: out_valid=%b out_last=%b", m_chunk, out_valid, out_last);
                    chk(out_valid === 1'b1 && out_last === (m_chunk == 2), s);
                    chk(in_ready === 1'b0 && dp_step_en === 1'b0, "OUT: in_ready/step_en high");
                    chk(busy === 1'b1, "OUT: busy low");
                    chk(dp_clear === (out_ready && m_chunk == 2), "OUT: dp_clear wrong");
                    if (!out_ready) m_ostall_cyc = m_ostall_cyc + 1;
                    if (out_ready) begin
                        if (m_chunk == 2) begin
                            // message done
                            if (mon_en && m_msg < NMSG) begin
                                $sformat(s, "msg %0d: blocks exp %0d got %0d",
                                         m_msg, plan_n[m_msg], m_blocks);
                                chk(m_blocks == plan_n[m_msg], s);
                                $sformat(s, "msg %0d: steps exp %0d got %0d",
                                         m_msg, 8 * m_blocks + 20, m_steps);
                                chk(m_steps == 8 * m_blocks + 20, s);
                                $sformat(s, "msg %0d: dp_clear count %0d", m_msg, m_clears);
                                chk(m_clears == 1, s);
                                if (!plan_install[m_msg] && !plan_ostall[m_msg]) begin
                                    $sformat(s, "msg %0d (n=%0d): cycles exp %0d got %0d",
                                             m_msg, m_blocks, 9 * m_blocks + 23,
                                             cyc - m_t0 + 1);
                                    chk(cyc - m_t0 + 1 == 9 * m_blocks + 23, s);
                                    $display("msg %0d: n=%0d  %0d cycles (9n+23 = %0d)",
                                             m_msg, m_blocks, cyc - m_t0 + 1, 9 * m_blocks + 23);
                                end
                                m_done_n[m_msg] = m_blocks;
                            end
                            m_msg = m_msg + 1;
                            mon_reset();
                        end else begin
                            m_chunk = m_chunk + 1;
                            mph = M_SQZ; e_idx = 0; e_max = 7;
                        end
                    end
                end
            endcase
        end
    end

    // ---- Receiver: random out_ready when the current message stalls ----
    always @(negedge clk) begin
        if (mon_en && m_msg < NMSG && plan_ostall[m_msg])
            out_ready = ($random(seed) & 1);
        else
            out_ready = 1'b1;
    end

    // ---- Sender ----
    task automatic send_msg(input integer n, input integer stall);
        integer b, k, idle;
        for (b = 0; b < n; b = b + 1) begin
            if (stall) begin
                in_valid = 0;
                idle = ($random(seed) & 3);
                for (k = 0; k < idle; k = k + 1) begin
                    @(negedge clk);
                    nstall_in = nstall_in + 1;
                end
            end
            in_valid = 1;
            in_last  = (b == n - 1);
            in_bytes = (b == n - 1) ? 5'(($random(seed) & 15) + 1) : 5'd16;
            // wait for the accept edge (in_ready is sampled before the edge)
            while (in_ready !== 1'b1) @(negedge clk);
            @(negedge clk);
            in_valid = 0;
            in_last  = ($random(seed) & 1);   // must not matter when idle
        end
    endtask

    // ---- Main ----
    integer i, t;
    initial begin
        nchk = 0; errs = 0; seed = 545; nstall_in = 0;
        rst = 1; in_valid = 0; in_last = 0; in_bytes = 0;
        @(negedge clk); @(negedge clk);
        rst = 0;

        // Plan messages: 0..4 no stalls back-to-back, 5..9 with stalls.
        for (i = 0; i < NMSG; i = i + 1) begin
            if (i == 5) begin
                // drain: wait for message 4 to finish so stall flags line up
                t = 0;
                while (m_msg < 5 && t < 2000) begin @(negedge clk); t = t + 1; end
            end
            send_msg(plan_n[i], plan_install[i]);
        end
        t = 0;
        while (m_msg < NMSG && t < 5000) begin @(negedge clk); t = t + 1; end
        chk(m_msg == NMSG, "timeout: not all messages finished");
        chk(nstall_in > 0,  "no sender stalls happened");
        chk(nstall_out > 0, "no receiver stalls happened");
        $display("messages done: %0d, sender stall cycles %0d, receiver stall cycles %0d",
                 m_msg, nstall_in, nstall_out);

        // ---- Reset mid-absorb ----
        mon_en = 0;
        in_valid = 1; in_last = 0; in_bytes = 16;
        while (in_ready !== 1'b1) @(negedge clk);
        @(negedge clk); in_valid = 0;
        repeat (3) @(negedge clk);
        chk(dp_step_en === 1'b1 && in_ready === 1'b0, "reset test 1: not absorbing");
        rst = 1; @(negedge clk); rst = 0;
        chk(in_ready === 1'b1 && busy === 1'b0 && dp_step_en === 1'b0 && out_valid === 1'b0,
            "reset mid-absorb: not back in WAIT next cycle");

        // ---- Reset mid-output (receiver holds out_ready low) ----
        in_valid = 1; in_last = 1; in_bytes = 3;
        @(negedge clk); in_valid = 0;
        t = 0;
        while (out_valid !== 1'b1 && t < 50) begin @(negedge clk); t = t + 1; end
        chk(out_valid === 1'b1, "reset test 2: D0 never valid");
        rst = 1; @(negedge clk); rst = 0;
        chk(in_ready === 1'b1 && busy === 1'b0 && out_valid === 1'b0 && dp_step_en === 1'b0,
            "reset mid-output: not back in WAIT next cycle");
        // after reset a full message still runs correctly (monitor checks it)
        t = m_msg;
        in_valid = 1; in_last = 1; in_bytes = 16;
        @(negedge clk); in_valid = 0;
        while (m_msg == t && cyc < 100000) @(negedge clk);
        chk(m_msg == t + 1, "message after reset did not finish");

        repeat (3) @(negedge clk);
        if (errs == 0) $display("TEST PASSED (%0d/%0d)", nchk, nchk);
        else           $display("TEST FAILED (%0d errors of %0d)", errs, nchk);
        $finish;
    end

    // watchdog
    initial begin
        #2000000;
        $display("TEST FAILED (watchdog timeout)");
        $finish;
    end
endmodule
