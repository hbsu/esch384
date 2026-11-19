// tb_esch384.sv
//
// Self-checking testbench for the Esch384 top level.
//
// Feeds every message of a KAT file through the core 16 bytes at a time,
// collects the three digest chunks, and compares the 48-byte digest with
// the MD line of the file.
//
// Plusargs (run_sim.sh passes them without the '+'):
//   KAT=<file>   KAT file to run. Default <VEC_DIR>/../kat/esch384_custom_kat.txt
//   ONLY=<n>     run only the record with Count = n (for debugging)
//   TRACE=1      print the state after every injection and every step, in
//                the same "TRACE <tag> x0 y0 ..." format as
//                sim/ref_build/esch_tool debug, so the two can be diffed
//   NOSTALL=1    never stall the sender or the receiver
//
// Checks per message: digest bytes, the handshake (a block moves only on
// valid and ready, the core is not ready while permuting, a digest chunk is
// held while the receiver backpressures), and, when neither side stalls,
// the cycle count against (8*NSUB + 2)*n + 20*NSUB + 4 for an n-block
// message, NSUB = 8/NALZ (NALZ = 8: 10n + 24).
//
// Parameter NALZ (8, 4, 2, 1) is passed to the DUT; set it with
//   NALZ=<n> scripts/run_sim.sh tb_esch384
//
// Prints TEST PASSED (N/N) or TEST FAILED (k errors of N).

`timescale 1ns/1ps
module tb_esch384;
    parameter integer NALZ = 8;
    localparam integer NSUB = 8 / NALZ;

    // ---------------------------------------------------------------- DUT
    logic         clk, rst;
    logic [127:0] blk_data;
    logic [4:0]   blk_bytes;
    logic         in_last, in_valid, in_ready;
    logic [127:0] digest_chunk;
    logic         out_valid, out_ready;

    esch384 #(.NALZ(NALZ)) dut (
        .clk          (clk),
        .rst          (rst),
        .blk_data     (blk_data),
        .blk_bytes    (blk_bytes),
        .in_last      (in_last),
        .in_valid     (in_valid),
        .in_ready     (in_ready),
        .digest_chunk (digest_chunk),
        .out_valid    (out_valid),
        .out_ready    (out_ready)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer cyc;
    always @(posedge clk) cyc = cyc + 1;

    // ------------------------------------------------------------ storage
    localparam integer MAXMSG = 1024;

    logic [7:0] msg    [0:MAXMSG-1];   // current message
    integer     msg_len;
    logic [7:0] md_exp [0:47];         // expected digest
    logic [7:0] md_got [0:47];         // digest from the core
    integer     kat_count;             // Count field of the current record

    integer nrec, nchk, errs, shown;
    integer only_n, trace_on, nostall;
    string  katfile, dir;

    localparam integer MAXSHOW = 8;    // at most this many failures printed

    // ------------------------------------------------------- hex handling
    // Value of one hex character, or -1 if it is not a hex digit.
    function automatic integer nibble(input logic [7:0] c);
        integer v;
        if (c >= 8'h30 && c <= 8'h39)      v = c - 8'h30;        // 0-9
        else if (c >= 8'h61 && c <= 8'h66) v = c - 8'h61 + 10;   // a-f
        else if (c >= 8'h41 && c <= 8'h46) v = c - 8'h41 + 10;   // A-F
        else                               v = -1;
        return v;
    endfunction

    function automatic integer starts_with(input string s, input string pre);
        integer r;
        if (s.len() < pre.len()) r = 0;
        else                     r = (s.substr(0, pre.len() - 1) == pre);
        return r;
    endfunction

    // Hex digits of s after the '=' go into msg[], msg_len.
    task automatic parse_msg(input string s);
        integer i, n, hi, v, seen_eq;
        n = 0; hi = -1; seen_eq = 0;
        for (i = 0; i < s.len(); i = i + 1) begin
            if (s.getc(i) == 8'h3D) seen_eq = 1;           // '='
            else if (seen_eq) begin
                v = nibble(s.getc(i));
                if (v >= 0) begin
                    if (hi < 0) hi = v;
                    else begin
                        if (n < MAXMSG) msg[n] = (hi * 16) + v;
                        n = n + 1;
                        hi = -1;
                    end
                end
            end
        end
        msg_len = n;
        if (n > MAXMSG) begin
            $display("ERROR: message longer than %0d bytes", MAXMSG);
            errs = errs + 1;
        end
    endtask

    // Hex digits of s after the '=' go into md_exp[]. Must be 48 bytes.
    task automatic parse_md(input string s);
        integer i, n, hi, v, seen_eq;
        n = 0; hi = -1; seen_eq = 0;
        for (i = 0; i < s.len(); i = i + 1) begin
            if (s.getc(i) == 8'h3D) seen_eq = 1;
            else if (seen_eq) begin
                v = nibble(s.getc(i));
                if (v >= 0) begin
                    if (hi < 0) hi = v;
                    else begin
                        if (n < 48) md_exp[n] = (hi * 16) + v;
                        n = n + 1;
                        hi = -1;
                    end
                end
            end
        end
        if (n != 48) begin
            $display("ERROR: MD line of record %0d has %0d bytes, expected 48",
                     kat_count, n);
            errs = errs + 1;
        end
    endtask

    // ------------------------------------------------------- debug trace
    // Mirrors esch_tool's "TRACE <tag> x0 y0 x1 y1 ... x7 y7".
    // The permutation's state register is what the reference prints, so the
    // tag is worked out from what the core did on the previous clock edge.
    logic   p_inject, p_squeeze, p_busy;
    integer t_blk, t_sq, t_squeezing;

    always @(posedge clk) begin
        p_inject  <= dut.do_inject;
        p_squeeze <= dut.do_squeeze;
        // a whole step finished on this edge (with shared Alzettes a step
        // takes several cycles; only print once it is complete)
        p_busy    <= dut.u_dp.u_perm.step_end;
    end

    task automatic print_state(input string tag);
        integer k;
        string  pad;
        // xsim right-justifies %-12s, so pad the tag by hand to match the
        // reference tool's "TRACE %-12s" exactly.
        pad = tag;
        while (pad.len() < 12) pad = {pad, " "};
        $write("TRACE %s", pad);
        for (k = 0; k < 16; k = k + 1)
            $write(" %08x", dut.u_dp.u_perm.state_reg[32*k +: 32]);
        $write("\n");
    endtask

    string ttag;

    always @(negedge clk) begin
        if (trace_on && !rst) begin
            if (p_inject) begin
                ttag = $sformatf("b%0d.inj", t_blk);
                print_state(ttag);
            end else if (p_squeeze) begin
                t_sq        = t_sq + 1;
                t_squeezing = 1;
            end else if (p_busy) begin
                if (t_squeezing)
                    ttag = $sformatf("sq%0d.s%0d", t_sq, dut.u_dp.u_perm.cnt - 1);
                else
                    ttag = $sformatf("b%0d.s%0d", t_blk, dut.u_dp.u_perm.cnt - 1);
                print_state(ttag);
                // last step of this block's permutation
                if (!t_squeezing && !dut.u_dp.u_perm.busy) t_blk = t_blk + 1;
            end
        end
    end

    // ------------------------------------------------------------- driver
    // Offer block bidx of the current message and wait until it is taken.
    task automatic send_block(input integer bidx, input integer nblk,
                              input integer stall, output integer bad);
        integer i, nb;
        logic [127:0] d;
        bad = 0;
        nb = msg_len - bidx * 16;
        if (nb > 16) nb = 16;
        if (nb < 0)  nb = 0;
        d = 128'd0;
        for (i = 0; i < nb; i = i + 1) d[8*i +: 8] = msg[bidx*16 + i];

        @(negedge clk);
        in_valid = 1'b0;
        blk_data = ~d;                      // garbage while not offering
        repeat (stall) @(negedge clk);      // sender is slow

        blk_data  = d;
        blk_bytes = (bidx == nblk - 1) ? nb[4:0] : 5'd16;
        in_last   = (bidx == nblk - 1);
        in_valid  = 1'b1;

        while (in_ready !== 1'b1) @(negedge clk);
        @(posedge clk);                     // taken on this edge
        @(negedge clk);
        in_valid = 1'b0;
        // After a block is taken the core is permuting, so it must not be
        // ready for another one.
        if (in_ready !== 1'b0) begin
            $display("ERROR record %0d: in_ready still high after taking block %0d",
                     kat_count, bidx);
            bad = 1;
        end
    endtask

    // Wait for a digest chunk and take it.
    task automatic recv_chunk(input integer stall, input integer idx,
                              output logic [127:0] c, output integer bad);
        integer k;
        bad = 0;
        @(negedge clk);
        out_ready = 1'b0;
        while (out_valid !== 1'b1) @(negedge clk);
        c = digest_chunk;
        // Hold off: the chunk must stay put while the receiver is not ready.
        for (k = 0; k < stall; k = k + 1) begin
            @(negedge clk);
            if (out_valid !== 1'b1 || digest_chunk !== c) begin
                $display("ERROR record %0d: chunk %0d not held during backpressure",
                         kat_count, idx);
                bad = 1;
            end
        end
        out_ready = 1'b1;
        @(posedge clk);                     // taken on this edge
        @(negedge clk);
        out_ready = 1'b0;
    endtask

    // ---------------------------------------------------- run one message
    task automatic run_record(input integer stall_in, input integer stall_out,
                              input integer check_cycles);
        integer b, nblk, i, bad, t0, t1, expc;
        logic [127:0] c0, c1, c2;

        bad  = 0;
        nblk = (msg_len + 15) / 16;
        if (nblk == 0) nblk = 1;            // empty message: one padded block

        t_blk = 0; t_sq = 0; t_squeezing = 0;
        if (trace_on) begin
            ttag = "init";
            print_state(ttag);              // state is zero before a message
        end

        for (b = 0; b < nblk; b = b + 1) begin
            send_block(b, nblk, (b == 0) ? 0 : stall_in, i);
            if (b == 0) t0 = cyc;           // sampled after the accepting edge
            if (i) bad = 1;
        end

        recv_chunk(stall_out, 0, c0, i); if (i) bad = 1;
        recv_chunk(stall_out, 1, c1, i); if (i) bad = 1;
        recv_chunk(stall_out, 2, c2, i); if (i) bad = 1;
        t1 = cyc;

        // The core must go back to accepting a new message on its own.
        if (out_valid !== 1'b0 || in_ready !== 1'b1) begin
            $display("ERROR record %0d: after D2 out_valid=%b in_ready=%b, expected 0 1",
                     kat_count, out_valid, in_ready);
            bad = 1;
        end

        for (i = 0; i < 16; i = i + 1) begin
            md_got[i]      = c0[8*i +: 8];
            md_got[16 + i] = c1[8*i +: 8];
            md_got[32 + i] = c2[8*i +: 8];
        end

        for (i = 0; i < 48; i = i + 1)
            if (md_got[i] !== md_exp[i]) begin
                if (!bad && shown < MAXSHOW)
                    $display("MISMATCH record %0d (%0d bytes): first bad digest byte %0d, exp %02X got %02X",
                             kat_count, msg_len, i, md_exp[i], md_got[i]);
                bad = 1;
            end

        if (bad && shown < MAXSHOW) begin
            shown = shown + 1;
            $write("  expected ");
            for (i = 0; i < 48; i = i + 1) $write("%02X", md_exp[i]);
            $write("\n  got      ");
            for (i = 0; i < 48; i = i + 1) $write("%02X", md_got[i]);
            $write("\n");
        end

        if (check_cycles) begin
            expc = (8 * NSUB + 2) * nblk + 20 * NSUB + 4;
            if (t1 - t0 != expc) begin
                $display("ERROR record %0d: %0d blocks took %0d cycles, expected %0d",
                         kat_count, nblk, t1 - t0, expc);
                bad = 1;
            end
        end

        nchk = nchk + 1;
        errs = errs + (bad != 0);
    endtask

    // ---------------------------------------------------------------- main
    integer fd, r, si, so, docyc;
    string  line;

    initial begin
        cyc = 0; nrec = 0; nchk = 0; errs = 0; shown = 0;
        msg_len = 0; kat_count = 0;
        p_inject = 0; p_squeeze = 0; p_busy = 0;
        t_blk = 0; t_sq = 0; t_squeezing = 0;
        rst = 1'b1; in_valid = 1'b0; in_last = 1'b0; out_ready = 1'b0;
        blk_data = 128'd0; blk_bytes = 5'd0;

        if (!$value$plusargs("ONLY=%d", only_n))  only_n   = -1;
        if (!$value$plusargs("TRACE=%d", trace_on)) trace_on = 0;
        if (!$value$plusargs("NOSTALL=%d", nostall)) nostall = 0;
        if (!$value$plusargs("KAT=%s", katfile)) begin
            if (!$value$plusargs("VEC_DIR=%s", dir)) dir = ".";
            katfile = {dir, "/../kat/esch384_custom_kat.txt"};
        end

        fd = $fopen(katfile, "r");
        if (fd == 0) begin
            $display("TEST FAILED (cannot open KAT file '%s')", katfile);
            $finish;
        end

        repeat (2) @(posedge clk);
        @(negedge clk); rst = 1'b0;
        @(negedge clk);

        while ($fgets(line, fd) > 0) begin
            if (starts_with(line, "Count")) begin
                kat_count = 0;
                r = $sscanf(line, "Count = %d", kat_count);
            end else if (starts_with(line, "Msg")) begin
                parse_msg(line);
            end else if (starts_with(line, "MD")) begin
                // Count, Msg and MD are all in: run this message.
                if (only_n < 0 || only_n == kat_count) begin
                    parse_md(line);
                    nrec = nrec + 1;
                    // Mix the stall patterns so the handshake is exercised
                    // both with and without a slow sender or receiver.
                    si = nostall ? 0 : (nrec % 3);
                    so = nostall ? 0 : ((nrec / 3) % 3);
                    docyc = (si == 0 && so == 0);
                    run_record(si, so, docyc);
                end
            end
        end
        $fclose(fd);

        $display("NALZ = %0d (%0d cycles per step)", NALZ, NSUB);
        if (nrec == 0)
            $display("TEST FAILED (no KAT records read from '%s')", katfile);
        else if (errs == 0)
            $display("TEST PASSED (%0d/%0d)", nchk, nchk);
        else
            $display("TEST FAILED (%0d errors of %0d)", errs, nchk);
        $finish;
    end

endmodule
