// tb_esch384.sv
// Self-checking KAT testbench for the esch384 top level.
// Vectors (made by scripts/gen_kat_vectors.py, format in its header):
//   <VEC_DIR>/kat_official.txt (1025 msgs), <VEC_DIR>/kat_custom.txt (34 msgs)
// Passes, all with ONE reset at the start (messages run back-to-back; the
// controller clears the state after D2):
//   1. official, no stalls    2. custom, no stalls
//   3. custom, random stalls on in_valid and out_ready (fixed seed)
// Per message checks: digest == MD; blocks accepted == blocks sent and
//   out_last only on D2; cycles (first accept .. D2 accept) == 9n+23
//   (no-stall passes only). Per pass: in_ready=1, busy=0 at the end;
//   stall pass: both kinds of stall really happened.
// Writes KAT-format files sim/tb_esch384/out_kat_<pass>.txt
//   (check with scripts/compare_kat.py <expected> <out>).
// Plusargs: +TRACE=<count> writes TRACE lines for that message (official
//   pass; +TRACE_SET=custom for the custom pass) to hw_trace.txt, same
//   format as `esch_tool debug`.
// Prints TEST PASSED (N/N) or TEST FAILED (k errors of N).
`timescale 1ns/1ps
module tb_esch384;
    logic         clk, rst;
    logic         in_valid, in_ready, in_last;
    logic [4:0]   in_bytes;
    logic [127:0] in_data;
    logic         out_valid, out_ready, out_last;
    logic [127:0] out_data;
    logic         busy;

    esch384 dut (.clk(clk), .rst(rst),
                 .in_valid(in_valid), .in_ready(in_ready), .in_last(in_last),
                 .in_bytes(in_bytes), .in_data(in_data),
                 .out_valid(out_valid), .out_ready(out_ready), .out_last(out_last),
                 .out_data(out_data), .busy(busy));

    initial clk = 0;
    always #5 clk = ~clk;

    // ---- Vector storage (one file at a time) ----
    localparam integer MAXM = 1200;
    localparam integer MAXB = 40000;
    logic [127:0] b_data  [0:MAXB-1];
    integer       b_bytes [0:MAXB-1];
    integer       m_count [0:MAXM-1];
    integer       m_len   [0:MAXM-1];
    integer       m_nblk  [0:MAXM-1];
    integer       m_first [0:MAXM-1];
    logic [383:0] m_md    [0:MAXM-1];
    integer       nmsg;

    integer nchk, errs, seed, cyc;
    string  dir, pname, s;
    integer stall_mode;       // current pass uses random stalls
    integer n_istall, n_ostall; // stall cycles seen (sender idle, receiver not ready)
    integer ofd, tfd;         // output KAT file, trace file
    integer tr_count, tr_pass_ok;
    string  tr_set;

    task automatic chk(input logic ok, input string what);
        nchk = nchk + 1;
        if (!ok) begin
            errs = errs + 1;
            if (errs <= 30) $display("ERROR: %s", what);
        end
    endtask

    task automatic load(input string path);
        integer fd, r, i, k, nb;
        string kw;
        fd = $fopen(path, "r");
        nmsg = 0; nb = 0;
        if (fd == 0) begin
            $display("ERROR: cannot open %s", path);
            return;
        end
        while (!$feof(fd) && nmsg < MAXM) begin
            r = $fscanf(fd, " %s", kw);
            if (r != 1) break;
            if (kw != "M") begin $display("ERROR format in %s: '%s'", path, kw); break; end
            r = $fscanf(fd, " %d %d %d", m_count[nmsg], m_len[nmsg], m_nblk[nmsg]);
            m_first[nmsg] = nb;
            for (i = 0; i < m_nblk[nmsg]; i = i + 1) begin
                r = $fscanf(fd, " %s %d %h", kw, b_bytes[nb], b_data[nb]);
                if (r != 3 || kw != "B") $display("ERROR format: block %0d", nb);
                nb = nb + 1;
            end
            r = $fscanf(fd, " %s %h", kw, m_md[nmsg]);
            if (r != 2 || kw != "D") $display("ERROR format: digest of msg %0d", nmsg);
            nmsg = nmsg + 1;
        end
        $fclose(fd);
        $display("loaded %s: %0d messages, %0d blocks", path, nmsg, nb);
    endtask

    // ---- Trace helpers ----
    function automatic string pad12(input string t);
        string r;
        r = t;
        while (r.len() < 12) r = {r, " "};
        return r;
    endfunction

    task automatic trace_state(input string tag);
        integer k;
        $fwrite(tfd, "TRACE %s", pad12(tag));
        for (k = 0; k < 16; k = k + 1)
            $fwrite(tfd, " %h", dut.u_dp.state_out[32*k +: 32]);
        $fwrite(tfd, "\n");
    endtask

    // ---- Monitor (samples at posedge, values before the edge) ----
    integer mi;               // current message index in the pass
    integer m_blk;            // blocks accepted for current message
    integer m_chunk;          // chunks accepted for current message
    integer m_t0;             // cycle of first accept
    integer m_lastbad;        // out_last wrong at some chunk
    integer done;             // messages finished in this pass
    logic [383:0] got;
    integer tr_on;            // tracing current message
    integer tr_pend;          // print state at next posedge
    string  tr_tag;

    task automatic finish_msg();
        integer k, b, ok_cyc, exp_cyc, ncyc;
        ncyc = cyc - m_t0 + 1;
        exp_cyc = 9 * m_nblk[mi] + 23;
        $sformat(s, "%s Count=%0d len=%0d: digest\n  expected %h\n  got      %h",
                 pname, m_count[mi], m_len[mi], m_md[mi], got);
        chk(got === m_md[mi], s);
        $sformat(s, "%s Count=%0d: blocks accepted %0d exp %0d, out_last bad=%0d",
                 pname, m_count[mi], m_blk, m_nblk[mi], m_lastbad);
        chk(m_blk == m_nblk[mi] && m_lastbad == 0, s);
        if (!stall_mode) begin
            $sformat(s, "%s Count=%0d (n=%0d): cycles exp %0d got %0d",
                     pname, m_count[mi], m_nblk[mi], exp_cyc, ncyc);
            chk(ncyc == exp_cyc, s);
        end
        // KAT-format output
        $fwrite(ofd, "Count = %0d\nMsg = ", m_count[mi]);
        for (b = m_first[mi]; b < m_first[mi] + m_nblk[mi]; b = b + 1)
            for (k = 0; k < b_bytes[b]; k = k + 1)
                $fwrite(ofd, "%h", b_data[b][8*k +: 8]);
        $fwrite(ofd, "\nMD = %h\n\n", got);
        mi = mi + 1; done = done + 1;
        m_blk = 0; m_chunk = 0; m_lastbad = 0; tr_on = 0;
    endtask

    always @(posedge clk) begin
        cyc = cyc + 1;
        if (tr_pend) begin
            trace_state(tr_tag);
            tr_pend = 0;
        end
        if (!rst && mi < nmsg) begin
            if (in_ready && !in_valid) n_istall = n_istall + 1;
            if (out_valid && !out_ready) n_ostall = n_ostall + 1;
            if (in_valid && in_ready) begin
                if (m_blk == 0) begin
                    m_t0 = cyc;
                    tr_on = tr_pass_ok && (m_count[mi] == tr_count);
                    if (tr_on) trace_state("init");
                end
                if (tr_on) begin
                    $sformat(tr_tag, "b%0d.inj", m_blk);
                    tr_pend = 1;
                end
                m_blk = m_blk + 1;
            end
            if (dut.u_ctrl.dp_step_en && tr_on) begin
                if (m_chunk == 0) $sformat(tr_tag, "b%0d.s%0d", m_blk - 1, dut.u_ctrl.dp_step_idx);
                else              $sformat(tr_tag, "sq%0d.s%0d", m_chunk, dut.u_ctrl.dp_step_idx);
                tr_pend = 1;
            end
            if (out_valid && out_ready) begin
                if (out_last !== (m_chunk == 2)) m_lastbad = m_lastbad + 1;
                for (int k = 0; k < 16; k++)
                    got[383 - 8*(16*m_chunk + k) -: 8] = out_data[8*k +: 8];
                m_chunk = m_chunk + 1;
                if (m_chunk == 3) finish_msg();
            end
        end
    end

    // ---- Receiver ----
    always @(negedge clk)
        out_ready = stall_mode ? ($random(seed) & 1) : 1'b1;

    // ---- Sender: all messages of the pass, back-to-back ----
    task automatic send_all();
        integer m, b, k, idle;
        for (m = 0; m < nmsg; m = m + 1) begin
            for (b = m_first[m]; b < m_first[m] + m_nblk[m]; b = b + 1) begin
                if (stall_mode) begin
                    // idle 0..3 cycles after in_ready rises (real stalls),
                    // junk on the other inputs meanwhile
                    in_valid = 0;
                    while (in_ready !== 1'b1) @(negedge clk);
                    idle = ($random(seed) & 3);
                    for (k = 0; k < idle; k = k + 1) begin
                        in_last  = ($random(seed) & 1);
                        in_bytes = $random(seed);
                        in_data  = {$random(seed), $random(seed), $random(seed), $random(seed)};
                        @(negedge clk);
                    end
                end
                in_valid = 1;
                in_last  = (b == m_first[m] + m_nblk[m] - 1);
                in_bytes = b_bytes[b][4:0];
                in_data  = b_data[b];
                while (in_ready !== 1'b1) @(negedge clk);
                @(negedge clk);
            end
        end
        in_valid = 0;
    endtask

    task automatic run_pass(input string name, input string file, input integer stall);
        integer t, pass_tr;
        string path;
        pname = name;
        path = {dir, "/", file};
        load(path);
        chk(nmsg > 0, {"no vectors read from ", path});
        stall_mode = stall;
        tr_pass_ok = (tr_count >= 0) && !stall &&
                     ((tr_set == "custom") ? (name == "custom") : (name == "official"));
        ofd = $fopen({"out_kat_", name, ".txt"}, "w");
        mi = 0; done = 0; m_blk = 0; m_chunk = 0; m_lastbad = 0; tr_on = 0;
        n_istall = 0; n_ostall = 0;
        @(negedge clk);
        send_all();
        t = 0;
        while (done < nmsg && t < 200000) begin @(negedge clk); t = t + 1; end
        $sformat(s, "%s: only %0d of %0d messages finished", name, done, nmsg);
        chk(done == nmsg, s);
        @(negedge clk);
        chk(in_ready === 1'b1 && busy === 1'b0 && out_valid === 1'b0,
            {name, ": not idle at end of pass"});
        if (stall) begin
            $sformat(s, "%s: stalls did not happen (in %0d, out %0d)", name, n_istall, n_ostall);
            chk(n_istall > 0 && n_ostall > 0, s);
        end
        $fclose(ofd);
        $display("pass %s: %0d messages, stall cycles in/out %0d/%0d, errors so far %0d, cycle %0d",
                 name, done, n_istall, n_ostall, errs, cyc);
        nmsg = 0;
    endtask

    // ---- Main ----
    initial begin
        nchk = 0; errs = 0; seed = 384; cyc = 0; nmsg = 0; mi = 0;
        tr_pend = 0; tr_on = 0; tr_pass_ok = 0; stall_mode = 0;
        if (!$value$plusargs("VEC_DIR=%s", dir)) dir = "ref/vectors";
        if (!$value$plusargs("TRACE=%d", tr_count)) tr_count = -1;
        if (!$value$plusargs("TRACE_SET=%s", tr_set)) tr_set = "official";
        tfd = $fopen("hw_trace.txt", "w");
        rst = 1; in_valid = 0; in_last = 0; in_bytes = 0; in_data = 0;
        @(negedge clk); @(negedge clk);
        rst = 0;           // only reset of the whole run

        run_pass("official",     "kat_official.txt", 0);
        run_pass("custom",       "kat_custom.txt",   0);
        run_pass("custom_stall", "kat_custom.txt",   1);

        $fclose(tfd);
        if (errs == 0) $display("TEST PASSED (%0d/%0d)", nchk, nchk);
        else           $display("TEST FAILED (%0d errors of %0d)", errs, nchk);
        $finish;
    end

    // watchdog
    initial begin
        #100000000;
        $display("TEST FAILED (watchdog timeout)");
        $finish;
    end
endmodule
