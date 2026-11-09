// tb_sparkle_linear.sv
// Self-checking testbench for sparkle_linear. Each vector line holds
// 16 hex input words (x0 y0 ... x7 y7), "|", then 16 hex output words.
// File path: +VEC=<path>, else <VEC_DIR>/linear.txt from +VEC_DIR=<dir>.
// Prints TEST PASSED (N/N) or TEST FAILED (k errors of N).
`timescale 1ns/1ps
module tb_sparkle_linear;
    logic [511:0] state_in, state_out, expv;
    logic [31:0]  w;
    string path, dir, sep;
    integer fd, r, k, n, errs, bad, ok;

    sparkle_linear dut (.state_in(state_in), .state_out(state_out));

    initial begin
        n = 0; errs = 0;
        if (!$value$plusargs("VEC=%s", path)) begin
            if ($value$plusargs("VEC_DIR=%s", dir)) path = {dir, "/linear.txt"};
            else path = "linear.txt";
        end
        fd = $fopen(path, "r");
        if (fd == 0) $display("ERROR: cannot open vector file '%s'", path);
        else begin
            while (!$feof(fd)) begin
                ok = 1;
                for (k = 0; k < 16 && ok; k = k + 1) begin
                    r = $fscanf(fd, " %h", w);
                    if (r != 1) ok = 0; else state_in[32*k +: 32] = w;
                end
                if (ok) begin
                    r = $fscanf(fd, " %s", sep);
                    if (r != 1 || sep != "|") begin
                        $display("ERROR: bad separator in vector %0d", n + 1);
                        ok = 0;
                    end
                end
                for (k = 0; k < 16 && ok; k = k + 1) begin
                    r = $fscanf(fd, " %h", w);
                    if (r != 1) ok = 0; else expv[32*k +: 32] = w;
                end
                if (ok) begin
                    n = n + 1;
                    #1;
                    bad = 0;
                    for (k = 0; k < 16; k = k + 1) begin
                        if (state_out[32*k +: 32] !== expv[32*k +: 32]) begin
                            bad = 1;
                            $display("MISMATCH line %0d word %0d (%s%0d): exp %h got %h",
                                     n, k, (k % 2) ? "y" : "x", k / 2,
                                     expv[32*k +: 32], state_out[32*k +: 32]);
                        end
                    end
                    errs = errs + bad;
                end
            end
            $fclose(fd);
        end
        if (n == 0) $display("TEST FAILED (no vectors read)");
        else if (errs == 0) $display("TEST PASSED (%0d/%0d)", n, n);
        else $display("TEST FAILED (%0d errors of %0d)", errs, n);
        $finish;
    end
endmodule
