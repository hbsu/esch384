// tb_esch_datapath.sv
// Self-checking testbench for esch_datapath. The TB acts as the controller.
// Vectors: +VEC=<path>, else <VEC_DIR>/datapath.txt (from +VEC_DIR=<dir>).
//   Made by scripts/gen_datapath_vectors.py (format in its header):
//   M idx len nblk / B bytes last block / S tag 16 words / D digest.
// Per message: clear (check 0); per block: inject, compare to <b>.inj,
//   then 8 steps (12 for the final block) with step_idx 0..N-1, comparing
//   after each; squeeze: D0 = digest_chunk, 8 steps, D1, 8 steps, D2,
//   comparing every step and each 16-byte chunk plus the 48-byte digest.
// Extra checks: hold (all controls low), clear+inject => 0, rst clears,
//   rst+inject => 0, clear+step_en => 0, inject beats step_en.
// Prints TEST PASSED (N/N) or TEST FAILED (k errors of N).
`timescale 1ns/1ps
module tb_esch_datapath;
    logic         clk, rst, clear, inject, step_en, msg_last;
    logic [3:0]   step_idx;
    logic [127:0] msg_block;
    logic [4:0]   msg_bytes;
    logic [511:0] state_out;
    logic [127:0] digest_chunk;

    esch_datapath dut (.clk(clk), .rst(rst), .clear(clear), .inject(inject),
                       .step_en(step_en), .step_idx(step_idx),
                       .msg_block(msg_block), .msg_bytes(msg_bytes),
                       .msg_last(msg_last), .state_out(state_out),
                       .digest_chunk(digest_chunk));

    initial clk = 0;
    always #5 clk = ~clk;

    integer fd, nchk, errs, nmsg, fmt_err;
    integer midx;                 // current message index (for messages)
    string  path, dir;

    // Saved from message 0, block 0 (for the priority test)
    logic [127:0] first_blk;
    logic [4:0]   first_bytes;
    logic         first_last;
    logic [511:0] first_inj;

    task check(input integer bad);
        nchk = nchk + 1;
        errs = errs + (bad != 0);
    endtask

    // Compare state_out to expv; print each wrong word. Returns 1 if bad.
    function automatic integer cmp_state(input logic [511:0] expv,
                                         input string tag);
        integer k, bad;
        bad = 0;
        for (k = 0; k < 16; k = k + 1)
            if (state_out[32*k +: 32] !== expv[32*k +: 32]) begin
                bad = 1;
                $display("MISMATCH msg %0d tag %s word %0d: exp %h got %h",
                         midx, tag, k, expv[32*k +: 32], state_out[32*k +: 32]);
            end
        return bad;
    endfunction

    // One clock with the given controls (inputs change at negedge).
    task pulse(input logic c_rst, input logic c_clear, input logic c_inj,
               input logic c_step, input logic [3:0] idx);
        rst = c_rst; clear = c_clear; inject = c_inj; step_en = c_step;
        step_idx = idx;
        @(negedge clk);
        rst = 0; clear = 0; inject = 0; step_en = 0;
        step_idx = $urandom;          // must not matter
    endtask

    // Read an "S <tag> words" line, check the tag is exp_tag, compare state.
    task read_s(input string exp_tag, output logic [511:0] expv);
        string kw, tag;
        integer r, k;
        logic [31:0] w;
        integer bad;
        bad = 0;
        expv = '0;
        r = $fscanf(fd, " %s %s", kw, tag);
        if (r != 2 || kw != "S" || tag != exp_tag) begin
            $display("ERROR format: msg %0d expected 'S %s', got '%s %s'",
                     midx, exp_tag, kw, tag);
            fmt_err = 1;
            bad = 1;
        end else begin
            for (k = 0; k < 16; k = k + 1) begin
                r = $fscanf(fd, " %h", w);
                if (r != 1) begin fmt_err = 1; bad = 1; end
                expv[32*k +: 32] = w;
            end
            if (!bad) bad = cmp_state(expv, tag);
        end
        check(bad);
    endtask

    // Process one message after its "M" header has been read.
    task run_msg(input integer len, input integer nblk);
        string kw, tag;
        integer r, b, s, nst, bytes_i, last_i, j, c, bad;
        logic [127:0] blk;
        logic [511:0] expv;
        logic [127:0] dch [0:2];
        logic [383:0] exp_dig, got_dig;

        // clear and check zero state
        msg_block = {4{$urandom}};
        pulse(0, 1, 0, 0, 0);
        bad = 0;
        if (state_out !== 512'd0) begin
            $display("MISMATCH msg %0d: state not 0 after clear", midx);
            bad = 1;
        end
        check(bad);

        for (b = 0; b < nblk && !fmt_err; b = b + 1) begin
            r = $fscanf(fd, " %s %d %d %h", kw, bytes_i, last_i, blk);
            if (r != 4 || kw != "B") begin
                $display("ERROR format: msg %0d block %0d bad B line", midx, b);
                fmt_err = 1;
            end else begin
                msg_block = blk; msg_bytes = bytes_i; msg_last = last_i;
                pulse(0, 0, 1, 0, 0);
                msg_block = ~blk; msg_bytes = $urandom; msg_last = ~last_i[0];
                tag = $sformatf("b%0d.inj", b);
                read_s(tag, expv);
                if (midx == 0 && b == 0) begin
                    first_blk = blk; first_bytes = bytes_i;
                    first_last = last_i; first_inj = expv;
                end
                nst = last_i ? 12 : 8;
                for (s = 0; s < nst && !fmt_err; s = s + 1) begin
                    pulse(0, 0, 0, 1, s);
                    tag = $sformatf("b%0d.s%0d", b, s);
                    read_s(tag, expv);
                end
            end
        end

        // squeeze
        dch[0] = digest_chunk;
        for (c = 1; c < 3 && !fmt_err; c = c + 1) begin
            for (s = 0; s < 8 && !fmt_err; s = s + 1) begin
                pulse(0, 0, 0, 1, s);
                tag = $sformatf("sq%0d.s%0d", c, s);
                read_s(tag, expv);
            end
            dch[c] = digest_chunk;
        end

        if (!fmt_err) begin
            r = $fscanf(fd, " %s %h", kw, exp_dig);
            if (r != 2 || kw != "D") begin
                $display("ERROR format: msg %0d bad D line", midx);
                fmt_err = 1;
            end else begin
                // digest byte j (j = 16c + i) = chunk c, bits [8i+7:8i];
                // exp_dig has byte 0 in its top 8 bits
                for (c = 0; c < 3; c = c + 1) begin
                    bad = 0;
                    for (j = 0; j < 16; j = j + 1) begin
                        got_dig[383 - 8*(16*c + j) -: 8] = dch[c][8*j +: 8];
                        if (dch[c][8*j +: 8] !== exp_dig[383 - 8*(16*c + j) -: 8])
                            bad = 1;
                    end
                    if (bad)
                        $display("MISMATCH msg %0d tag D%0d: exp %h got %h", midx, c,
                                 exp_dig[383 - 128*c -: 128], got_dig[383 - 128*c -: 128]);
                    check(bad);
                end
                bad = (got_dig !== exp_dig);
                if (bad)
                    $display("MISMATCH msg %0d tag digest (len %0d): exp %h got %h",
                             midx, len, exp_dig, got_dig);
                check(bad);
            end
        end
    endtask

    integer r, len, nblk, k, bad;
    string  kw;
    logic [511:0] held;

    initial begin
        nchk = 0; errs = 0; nmsg = 0; fmt_err = 0; midx = -1;
        rst = 1; clear = 0; inject = 0; step_en = 0; step_idx = 0;
        msg_block = '0; msg_bytes = 0; msg_last = 0;
        if (!$value$plusargs("VEC=%s", path)) begin
            if ($value$plusargs("VEC_DIR=%s", dir)) path = {dir, "/datapath.txt"};
            else path = "datapath.txt";
        end
        repeat (2) @(posedge clk);
        @(negedge clk); rst = 0;

        fd = $fopen(path, "r");
        if (fd == 0) $display("ERROR: cannot open vector file '%s'", path);
        else begin
            while (!$feof(fd) && !fmt_err) begin
                r = $fscanf(fd, " %s", kw);
                if (r == 1) begin
                    if (kw != "M") begin
                        $display("ERROR format: expected M, got '%s'", kw);
                        fmt_err = 1;
                    end else begin
                        r = $fscanf(fd, " %d %d %d", midx, len, nblk);
                        if (r != 3) fmt_err = 1;
                        else begin
                            run_msg(len, nblk);
                            nmsg = nmsg + 1;
                        end
                    end
                end
            end
            $fclose(fd);
        end
        if (fmt_err) errs = errs + 1;

        if (nmsg > 0) begin
            midx = -1;
            // 1) hold: all controls low keeps the (nonzero) state
            held = state_out;
            bad = (held === 512'd0);
            for (k = 0; k < 5; k = k + 1) begin
                msg_block = {4{$urandom}}; msg_bytes = $urandom; msg_last = $urandom;
                step_idx = $urandom;
                @(negedge clk);
                if (state_out !== held) bad = 1;
            end
            if (bad) $display("ERROR hold: state changed with all controls low");
            check(bad);

            // 2) clear + inject => 0
            msg_block = first_blk; msg_bytes = first_bytes; msg_last = first_last;
            pulse(0, 1, 1, 0, 0);
            bad = (state_out !== 512'd0);
            if (bad) $display("ERROR priority: clear+inject did not give 0");
            check(bad);

            // 3) inject + step_en => injection wins (expected b0.inj of msg 0)
            pulse(0, 0, 1, 1, 0);
            bad = cmp_state(first_inj, "prio-inject-over-step");
            check(bad);

            // 4) clear + step_en => 0
            pulse(0, 1, 0, 1, 3);
            bad = (state_out !== 512'd0);
            if (bad) $display("ERROR priority: clear+step_en did not give 0");
            check(bad);

            // 5) rst clears a nonzero state
            pulse(0, 0, 1, 0, 0);
            pulse(0, 0, 0, 1, 0);
            bad = (state_out === 512'd0);
            pulse(1, 0, 0, 0, 0);
            if (state_out !== 512'd0) bad = 1;
            if (bad) $display("ERROR rst: state not cleared");
            check(bad);

            // 6) rst + inject => 0
            pulse(1, 0, 1, 1, 0);
            bad = (state_out !== 512'd0);
            if (bad) $display("ERROR priority: rst+inject did not give 0");
            check(bad);
        end

        if (nmsg == 0) $display("TEST FAILED (no vectors read)");
        else if (errs == 0) $display("TEST PASSED (%0d/%0d)", nchk, nchk);
        else $display("TEST FAILED (%0d errors of %0d)", errs, nchk);
        $finish;
    end
endmodule
