// tb_sparkle512.sv
// Self-checking testbench for sparkle512 (iterative, 1 step/cycle).
// Vectors: <VEC_DIR>/sparkle512_slim8.txt (big=0) and
//          <VEC_DIR>/sparkle512_big12.txt (big=1), from +VEC_DIR=<dir>.
//          Each line: 16 hex input words, "|", 16 hex output words.
// Per vector: pulse start, check done comes exactly 9 (slim) / 13 (big)
//   cycles after the start cycle, busy high until done, busy low at done,
//   state_out correct and held stable while idle.
// Extra checks: start while busy ignored, reset mid-run, back-to-back runs.
// Prints TEST PASSED (N/N) or TEST FAILED (k errors of N).
`timescale 1ns/1ps
module tb_sparkle512;
    logic         clk, rst, start, big;
    logic [511:0] state_in, state_out;
    logic         busy, done;

    sparkle512 dut (.clk(clk), .rst(rst), .start(start), .big(big),
                    .state_in(state_in), .state_out(state_out),
                    .busy(busy), .done(done));

    initial clk = 0;
    always #5 clk = ~clk;

    // Vector storage
    logic [511:0] vin  [0:255];
    logic [511:0] vexp [0:255];
    logic         vbig [0:255];
    integer       vline[0:255];
    integer       nvec, nchk, errs;

    string dir;

    task automatic load_file(input string path, input logic b);
        integer fd, r, k, line, ok;
        logic [31:0] w;
        logic [511:0] a, e;
        string sep;
        fd = $fopen(path, "r");
        if (fd == 0) begin
            $display("ERROR: cannot open vector file '%s'", path);
            return;
        end
        line = 0;
        while (!$feof(fd)) begin
            ok = 1;
            for (k = 0; k < 16 && ok; k = k + 1) begin
                r = $fscanf(fd, " %h", w);
                if (r != 1) ok = 0; else a[32*k +: 32] = w;
            end
            if (ok) begin
                r = $fscanf(fd, " %s", sep);
                if (r != 1 || sep != "|") begin
                    $display("ERROR: bad separator in %s line %0d", path, line + 1);
                    ok = 0;
                end
            end
            for (k = 0; k < 16 && ok; k = k + 1) begin
                r = $fscanf(fd, " %h", w);
                if (r != 1) ok = 0; else e[32*k +: 32] = w;
            end
            if (ok) begin
                line = line + 1;
                vin[nvec] = a; vexp[nvec] = e; vbig[nvec] = b; vline[nvec] = line;
                nvec = nvec + 1;
            end
        end
        $fclose(fd);
    endtask

    // Compare state_out to expected; print word mismatches. Returns 1 if bad.
    function automatic integer cmp_state(input logic [511:0] expv, input string tag,
                                         input integer line);
        integer k, bad;
        bad = 0;
        for (k = 0; k < 16; k = k + 1)
            if (state_out[32*k +: 32] !== expv[32*k +: 32]) begin
                bad = 1;
                $display("MISMATCH %s line %0d word %0d (%s%0d): exp %h got %h",
                         tag, line, k, (k % 2) ? "y" : "x", k / 2,
                         expv[32*k +: 32], state_out[32*k +: 32]);
            end
        return bad;
    endfunction

    // Run vector idx. Inputs change on negedge. Returns at the negedge of
    // the done cycle (so a caller may assert start in that same cycle).
    // If hold=1, also idles 3 cycles and checks state_out is held, done low.
    // If busy_poke=1, pulses start with garbage input for 3 cycles mid-run.
    task run_vec(input integer idx, input integer hold,
                           input integer busy_poke, input string tag,
                           output integer bad);
        integer cyc, nexp, k;
        bad  = 0;
        nexp = vbig[idx] ? 13 : 9;
        start = 1; big = vbig[idx]; state_in = vin[idx];
        @(posedge clk);            // start sampled here (counts as cycle 1)
        cyc = 1;
        @(negedge clk);
        start = 0; big = ~vbig[idx]; state_in = ~vin[idx];  // must not matter
        while (!done && cyc < 40) begin
            if (busy !== 1'b1) begin
                if (!bad) $display("ERROR %s line %0d: busy low before done (cycle %0d)",
                                   tag, vline[idx], cyc);
                bad = 1;
            end
            if (busy_poke && cyc >= 3 && cyc < 6) start = 1; else start = 0;
            @(posedge clk); cyc = cyc + 1;
            @(negedge clk);
        end
        start = 0;
        if (cyc != nexp) begin
            $display("ERROR %s line %0d: done after %0d cycles, expected %0d",
                     tag, vline[idx], cyc, nexp);
            bad = 1;
        end
        if (busy !== 1'b0) begin
            $display("ERROR %s line %0d: busy high in done cycle", tag, vline[idx]);
            bad = 1;
        end
        if (cmp_state(vexp[idx], tag, vline[idx])) bad = 1;
        if (hold) begin
            for (k = 0; k < 3; k = k + 1) begin
                @(negedge clk);
                if (done !== 1'b0 || busy !== 1'b0) begin
                    $display("ERROR %s line %0d: done/busy not low while idle",
                             tag, vline[idx]);
                    bad = 1;
                end
                if (cmp_state(vexp[idx], tag, vline[idx])) bad = 1;
            end
        end
    endtask

    task check(input integer bad);
        nchk = nchk + 1;
        errs = errs + (bad != 0);
    endtask

    integer i, b1, b2, slim0, big0;
    string  tagv;

    initial begin
        nvec = 0; nchk = 0; errs = 0;
        rst = 1; start = 0; big = 0; state_in = '0;
        if (!$value$plusargs("VEC_DIR=%s", dir)) dir = ".";
        load_file({dir, "/sparkle512_slim8.txt"}, 1'b0);
        slim0 = 0;
        big0  = nvec;
        load_file({dir, "/sparkle512_big12.txt"}, 1'b1);

        repeat (2) @(posedge clk);
        @(negedge clk); rst = 0;
        @(negedge clk);

        if (nvec > 0) begin
            // 1) All vectors, idle between runs
            for (i = 0; i < nvec; i = i + 1) begin
                if (vbig[i]) tagv = "big"; else tagv = "slim";
                run_vec(i, 1, 0, tagv, b1);
                check(b1);
            end

            // 2) start while busy is ignored (slim and big)
            run_vec(slim0 + 1, 1, 1, "slim-poke", b1); check(b1);
            if (big0 < nvec) begin run_vec(big0 + 1, 1, 1, "big-poke", b1); check(b1); end

            // 3) reset mid-run, then a fresh run
            b1 = 0;
            start = 1; big = 1; state_in = vin[nvec - 1];
            @(negedge clk); start = 0;
            repeat (4) @(negedge clk);
            rst = 1;
            @(negedge clk); rst = 0;
            if (busy !== 1'b0 || done !== 1'b0 || state_out !== 512'd0) begin
                $display("ERROR reset: busy=%b done=%b state_out nonzero=%b",
                         busy, done, |state_out);
                b1 = 1;
            end
            check(b1);
            run_vec(slim0 + 2, 1, 0, "after-reset", b1); check(b1);

            // 4) back-to-back: next start asserted in the done cycle
            run_vec(slim0 + 3, 0, 0, "b2b-1", b1);
            run_vec(big0 < nvec ? big0 + 3 : slim0 + 4, 0, 0, "b2b-2", b2);
            check(b1); check(b2);
            run_vec(slim0 + 5, 1, 0, "b2b-3", b1); check(b1);
        end

        if (nvec == 0) $display("TEST FAILED (no vectors read)");
        else if (errs == 0) $display("TEST PASSED (%0d/%0d)", nchk, nchk);
        else $display("TEST FAILED (%0d errors of %0d)", errs, nchk);
        $finish;
    end
endmodule
