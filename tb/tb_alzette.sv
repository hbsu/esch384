// tb_alzette.sv
// Self-checking testbench for alzette. Reads vectors "c x y u v" (hex),
// one per line. File path: +VEC=<path>, else <VEC_DIR>/alzette.txt
// from +VEC_DIR=<dir>. Prints TEST PASSED (N/N) or TEST FAILED (k errors of N).
`timescale 1ns/1ps
module tb_alzette;
    logic [31:0] x_in, y_in, c, x_out, y_out;
    logic [31:0] vc, vx, vy, vu, vv;
    string path, dir;
    integer fd, r, n, errs;

    alzette dut (.x_in(x_in), .y_in(y_in), .c(c), .x_out(x_out), .y_out(y_out));

    initial begin
        n = 0; errs = 0;
        if (!$value$plusargs("VEC=%s", path)) begin
            if ($value$plusargs("VEC_DIR=%s", dir)) path = {dir, "/alzette.txt"};
            else path = "alzette.txt";
        end
        fd = $fopen(path, "r");
        if (fd == 0) $display("ERROR: cannot open vector file '%s'", path);
        else begin
            while (!$feof(fd)) begin
                r = $fscanf(fd, "%h %h %h %h %h\n", vc, vx, vy, vu, vv);
                if (r == 5) begin
                    n = n + 1;
                    c = vc; x_in = vx; y_in = vy;
                    #1;
                    if (x_out !== vu || y_out !== vv) begin
                        errs = errs + 1;
                        $display("MISMATCH line %0d: c=%h x=%h y=%h exp u=%h v=%h got u=%h v=%h",
                                 n, vc, vx, vy, vu, vv, x_out, y_out);
                    end
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
