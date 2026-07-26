// ============================================================================
// Sequence: adc_calib_seq
// Description: Calibration test sequence
//              CAL_001: Normal calibration — write CAL_ST=1, poll CAL_DONE=1
//              CAL_002: Read CAL_VAL after completion
//              CAL_003: Calibration + sampling parallel (no mutex, per spec §3.7)
//              CAL_004: CAL_DONE level-following (high multiple cycles → reads 1)
//              CAL_005: CAL_DONE level clear (CAL_ST=0 → CAL_DONE follows to 0)
//              REG_STAT_CAL_BUSY: STAT[3] CAL_BUSY=1 during cal, =0 after
//              CAL_20CYCLE: calibration completes in ~20 ADC_CLK cycles (800ns)
//              CAL_ST_DIRECT: CAL_ST is PCLK RW bit direct to analog (no CDC)
//              CAL_DONE_SYNC: CAL_DONE 2-stage sync (cal_done_s1/s2) verified
//              CAL_NO_TIMEOUT: controller has no timeout; CAL_BUSY=1 while
//                              cal in progress, =0 after completion.
//
//              Calibration is auto-driven by the hardware analog model
//              (adc_analog_model): writing CAL_CTRL[0]=1 sets cal_st (PCLK RW
//              bit, direct to analog); the model completes after ~20 ADC_CLK
//              cycles and raises cal_done (level) + cal_val on its own. The
//              sequence only triggers calibration and polls the registers — it
//              does NOT drive m_vif.cal_done/cal_val.
//
//              Per spec §3.7: controller does NOT enforce calibration/sampling
//              mutex (software responsibility). CAL_DONE is a level (not sticky).
// ============================================================================

class adc_calib_seq extends adc_base_seq;
    `uvm_object_utils(adc_calib_seq)

    function new(string name = "adc_calib_seq");
        super.new(name);
    endfunction

    // Poll CAL_DONE (CAL_CTRL[1]) until set, with a timeout.
    task wait_cal_done(input integer max_poll);
        bit [31:0] rd;
        integer n;
        n = 0;
        forever begin
            apb_read(`ADC_CAL_CTRL, rd);
            if (rd[1]) return;
            n = n + 1;
            if (n > max_poll) begin
                `uvm_error(get_type_name(), "[FAIL] CAL_DONE not observed (timeout)")
                return;
            end
            #200;
        end
    endtask

    task body();
        bit [31:0] rd;
        bit cal_done_ok;
        bit sample_ok;

        `uvm_info(get_type_name(), "=== Calibration Test ===", UVM_LOW)
        #300;

        // Enable ADC (required to calibrate; analog clears cal_done when ADC_EN=0)
        apb_write(`ADC_CTRL, 32'h0000_0001);
        #200;

        // --- CAL_001: Start calibration ---
        apb_write(`ADC_CAL_CTRL, 32'h0000_0001);  // CAL_ST=1
        #200;
        apb_read(`ADC_CAL_CTRL, rd);
        if (rd[0]) begin
            `uvm_info(get_type_name(), "[PASS] CAL_001: CAL_ST set after write", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), "[FAIL] CAL_001: CAL_ST not set")
        end

        // Calibration auto-completes in the analog model; poll for CAL_DONE.
        wait_cal_done(50);

        // CAL_ST stays 1 until software clears it (not self-cleared).
        apb_read(`ADC_CAL_CTRL, rd);
        if (rd[0]) begin
            `uvm_info(get_type_name(), "[PASS] CAL_001: CAL_ST still 1 (software must clear)", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), "[FAIL] CAL_001: CAL_ST unexpectedly 0")
        end

        // --- CAL_002: Read calibration value ---
        apb_read(`ADC_CAL_VAL, rd);
        if (rd[5:0] == 6'h2A) begin
            `uvm_info(get_type_name(), $sformatf("[PASS] CAL_002: CAL_VAL = 0x%02h", rd[5:0]), UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), $sformatf("[FAIL] CAL_002: CAL_VAL = 0x%02h, expected 0x2A", rd[5:0]))
        end

        // --- CAL_004: CAL_DONE level-following (multiple reads stay 1) ---
        // cal_done is a level (cal_done_s2), not sticky. While CAL_ST=1 and
        // cal_done high, repeated reads of CAL_CTRL[1] should stay 1.
        apb_read(`ADC_CAL_CTRL, rd);
        if (rd[1]) begin
            #500;  // wait a few more cycles, cal_done still high (CAL_ST still 1)
            apb_read(`ADC_CAL_CTRL, rd);
            if (rd[1]) begin
                `uvm_info(get_type_name(), "[PASS] CAL_004: CAL_DONE stays 1 while CAL_ST=1 (level follow)", UVM_LOW)
            end else begin
                `uvm_error(get_type_name(), "[FAIL] CAL_004: CAL_DONE dropped while CAL_ST still 1")
            end
        end else begin
            `uvm_error(get_type_name(), "[FAIL] CAL_004: CAL_DONE not 1 after wait_cal_done")
        end

        // --- CAL_005: CAL_DONE level clear (CAL_ST=0 → CAL_DONE follows to 0) ---
        // CAL_DONE is NOT a sticky bit — it follows cal_done level. Writing
        // CAL_ST=0 makes analog drop cal_done, which propagates (2-cycle sync)
        // to CAL_CTRL[1]=0.
        apb_write(`ADC_CAL_CTRL, 32'h0000_0000);  // CAL_ST=0
        #1000;  // wait for analog cal_done↓ + 2-cycle CDC sync
        apb_read(`ADC_CAL_CTRL, rd);
        if (!rd[1] && !rd[0]) begin
            `uvm_info(get_type_name(), "[PASS] CAL_005: CAL_DONE followed CAL_ST=0 to 0 (level, not sticky)", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), $sformatf("[FAIL] CAL_005: CAL_CTRL=0x%04h after CAL_ST=0 (exp both 0)", rd[15:0]))
        end

        // --- CAL_003: Calibration + sampling parallel (spec §3.7: no mutex) ---
        // Per spec: controller does NOT enforce mutex. Verify calibration and
        // sampling run in parallel without conflict: CAL_ST=1 + trigger LP sample,
        // both CAL_DONE and CH_DATA VALID should assert (no blocking).
        `uvm_info(get_type_name(), "=== CAL_003: cal + sampling parallel (no mutex) ===", UVM_LOW)
        apb_write(`ADC_CTRL, 32'h0000_0002); #2000;  // SW_RST
        apb_write(`ADC_CTRL, 32'h0000_0001); #200;   // ADC_EN=1
        // Start calibration
        apb_write(`ADC_CAL_CTRL, 32'h0000_0001);  // CAL_ST=1
        #100;
        // Trigger LP sampling while calibration in progress
        write_lp_seq_single(5'h03);  // CH3 (also sets LP_SEQ_LEN=1)
        apb_write(`ADC_TRIG, 32'h0000_0002);
        apb_write(`ADC_TRIG, 32'h0000_0003);
        #15000;  // wait for both cal (20 cyc) and 1-entry sample to complete
        // Check both completed — no mutex blocked either
        apb_read(`ADC_CAL_CTRL, rd);
        cal_done_ok = rd[1];
        apb_read(`ADC_LP_DATA0 + 0*4, rd);  // LP slot 0 (CH3)
        sample_ok = rd[31];
        if (cal_done_ok && sample_ok) begin
            `uvm_info(get_type_name(), "[PASS] CAL_003: cal + sampling both completed (parallel, no mutex per spec)", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), $sformatf("[FAIL] CAL_003: cal_done=%0d sample_valid=%0d (one blocked?)", cal_done_ok, sample_ok))
        end
        // Clean up: clear CAL_ST
        apb_write(`ADC_CAL_CTRL, 32'h0000_0000);
        #500;

        // --- Additional calibration test points ---
        reg_stat_cal_busy();        // REG_STAT_CAL_BUSY
        cal_20cycle();              // CAL_20CYCLE
        cal_st_direct();            // CAL_ST_DIRECT
        cal_done_sync();            // CAL_DONE_SYNC
        cal_no_timeout();           // CAL_NO_TIMEOUT

        `uvm_info(get_type_name(), "Calibration test complete", UVM_LOW)
    endtask

    // ────────────────────────────────────────────────────────────────────────
    // REG_STAT_CAL_BUSY: STAT[3] CAL_BUSY=1 during calibration, =0 after.
    //   cal_busy = cfg_cal_st & ~cal_done (PCLK), 2-stage synced to cal_busy_s2
    //   for STAT[3] read. While cal in progress (CAL_ST=1, cal_done=0):
    //   cal_busy=1 → STAT[3]=1. After cal_done rises: cal_busy=0 → STAT[3]=0.
    // ────────────────────────────────────────────────────────────────────────
    task reg_stat_cal_busy();
        bit [31:0] rd;
        `uvm_info(get_type_name(), "=== REG_STAT_CAL_BUSY ===", UVM_LOW)
        // SW_RST for clean slate
        apb_write(`ADC_CTRL, 32'h0000_0002); #2000;
        apb_write(`ADC_CTRL, 32'h0000_0001); #200;  // ADC_EN=1
        // Start calibration
        apb_write(`ADC_CAL_CTRL, 32'h0000_0001);  // CAL_ST=1
        #200;  // a few PCLK — cal just started, cal_done not yet
        apb_read(`ADC_STAT, rd);
        if (rd[3]) begin
            `uvm_info(get_type_name(),
                "[PASS] REG_STAT_CAL_BUSY: STAT[3]=1 during calibration (cal_busy=1)", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(),
                $sformatf("[FAIL] REG_STAT_CAL_BUSY: STAT[3]=0 during calibration (STAT=0x%04h)", rd[15:0]))
        end
        // Wait for cal_done
        wait_cal_done(50);
        // Allow cal_busy_s2 to sync clear (cal_busy=0 after cal_done rises)
        #500;
        apb_read(`ADC_STAT, rd);
        if (!rd[3]) begin
            `uvm_info(get_type_name(),
                "[PASS] REG_STAT_CAL_BUSY: STAT[3]=0 after calibration done (cal_busy=0)", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(),
                $sformatf("[FAIL] REG_STAT_CAL_BUSY: STAT[3]=1 after cal done (STAT=0x%04h)", rd[15:0]))
        end
        // Clean up
        apb_write(`ADC_CAL_CTRL, 32'h0000_0000);
        #500;
    endtask

    // ────────────────────────────────────────────────────────────────────────
    // CAL_20CYCLE: calibration fixed 20 ADC_CLK cycles → CAL_DONE set.
    //   ADC_CLK=25MHz (40ns period). 20 cycles = 800ns. Measure elapsed time
    //   from CAL_ST=1 to CAL_CTRL[1]=1. Allow CDC sync margin (2 PCLK + 2 adc).
    // ────────────────────────────────────────────────────────────────────────
    task cal_20cycle();
        bit [31:0] rd;
        time t_start, t_end;
        time t_elapsed;
        `uvm_info(get_type_name(), "=== CAL_20CYCLE: 20 ADC_CLK cycle calibration ===", UVM_LOW)
        apb_write(`ADC_CTRL, 32'h0000_0002); #2000;  // SW_RST
        apb_write(`ADC_CTRL, 32'h0000_0001); #200;   // ADC_EN=1
        t_start = $time;
        apb_write(`ADC_CAL_CTRL, 32'h0000_0001);  // CAL_ST=1
        // Poll for CAL_DONE with generous timeout (50 polls × 200ns = 10us)
        wait_cal_done(50);
        t_end = $time;
        t_elapsed = t_end - t_start;
        // Expected ~800ns (20 * 40ns) + CDC sync (2 adc_clk=80ns) + APB poll latency
        // Allow 600ns..3000ns window (poll interval 200ns adds up to 200ns jitter).
        `uvm_info(get_type_name(),
            $sformatf("  CAL_DONE elapsed: %0dns (expected ~800ns + sync margin)", t_elapsed), UVM_LOW)
        if (t_elapsed >= 600 && t_elapsed <= 3000) begin
            `uvm_info(get_type_name(),
                $sformatf("[PASS] CAL_20CYCLE: elapsed=%0dns within 600~3000ns window (~20 ADC_CLK)", t_elapsed), UVM_LOW)
        end else begin
            `uvm_error(get_type_name(),
                $sformatf("[FAIL] CAL_20CYCLE: elapsed=%0dns outside 600~3000ns window", t_elapsed))
        end
        apb_write(`ADC_CAL_CTRL, 32'h0000_0000);
        #500;
    endtask

    // ────────────────────────────────────────────────────────────────────────
    // CAL_ST_DIRECT: CAL_ST is a PCLK RW register bit direct to analog (no CDC).
    //   Write CAL_CTRL[0]=1 → immediate readback=1. Write 0 → immediate readback=0.
    //   "Immediate" means same-cycle register read — no synchronization delay.
    // ────────────────────────────────────────────────────────────────────────
    task cal_st_direct();
        bit [31:0] rd;
        `uvm_info(get_type_name(), "=== CAL_ST_DIRECT: PCLK RW direct (no CDC) ===", UVM_LOW)
        apb_write(`ADC_CTRL, 32'h0000_0002); #2000;  // SW_RST
        apb_write(`ADC_CTRL, 32'h0000_0001); #200;   // ADC_EN=1
        // Write CAL_ST=1
        apb_write(`ADC_CAL_CTRL, 32'h0000_0001);
        // Immediate readback — no settling delay needed (PCLK domain RW bit)
        apb_read(`ADC_CAL_CTRL, rd);
        if (rd[0]) begin
            `uvm_info(get_type_name(),
                "[PASS] CAL_ST_DIRECT: CAL_ST=1 immediate readback (no CDC delay)", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(),
                $sformatf("[FAIL] CAL_ST_DIRECT: CAL_ST=1 readback=0 (rd=0x%04h)", rd[15:0]))
        end
        // Write CAL_ST=0
        apb_write(`ADC_CAL_CTRL, 32'h0000_0000);
        apb_read(`ADC_CAL_CTRL, rd);
        if (!rd[0]) begin
            `uvm_info(get_type_name(),
                "[PASS] CAL_ST_DIRECT: CAL_ST=0 immediate readback (no CDC delay)", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(),
                $sformatf("[FAIL] CAL_ST_DIRECT: CAL_ST=0 readback=1 (rd=0x%04h)", rd[15:0]))
        end
    endtask

    // ────────────────────────────────────────────────────────────────────────
    // CAL_DONE_SYNC: CAL_DONE is 2-stage synced (cal_done_s1/s2) before read.
    //   After CAL_ST=1 and cal done completes:
    //     - CAL_CTRL[1] (= cal_done_s2) stays 1 (level follow) while CAL_ST=1
    //     - Use uvm_hdl_read on cal_done_s1/s2 to verify sync chain
    //     - After CAL_ST=0: cal_done drops → cal_done_s1 then s2 clear ~2 PCLK
    // ────────────────────────────────────────────────────────────────────────
    task cal_done_sync();
        bit [31:0] rd;
        bit s1_val, s2_val;
        string s1_hier = "tb_top.u_dut.u_regfile.gen_active.cal_done_s1";
        string s2_hier = "tb_top.u_dut.u_regfile.gen_active.cal_done_s2";
        `uvm_info(get_type_name(), "=== CAL_DONE_SYNC: 2-stage sync chain ===", UVM_LOW)
        apb_write(`ADC_CTRL, 32'h0000_0002); #2000;  // SW_RST
        apb_write(`ADC_CTRL, 32'h0000_0001); #200;   // ADC_EN=1
        apb_write(`ADC_CAL_CTRL, 32'h0000_0001);  // CAL_ST=1
        wait_cal_done(50);
        // CAL_CTRL[1] should be 1 (cal_done_s2=1)
        apb_read(`ADC_CAL_CTRL, rd);
        if (rd[1]) begin
            `uvm_info(get_type_name(),
                "[PASS] CAL_DONE_SYNC: CAL_CTRL[1]=1 after cal done (cal_done_s2=1)", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(),
                "[FAIL] CAL_DONE_SYNC: CAL_CTRL[1]=0 after cal done")
        end
        // Backdoor check sync chain
        // GATE_SIM guard: cal_done_s1/s2 are RTL-internal sync regs, renamed in
        // gate netlist → uvm_hdl_read returns 0. Frontdoor CAL_CTRL[1] read
        // (above, already PASS) validates the sync chain end-to-end.
`ifdef GATE_SIM
        void'(uvm_hdl_read(s1_hier, s1_val));
        void'(uvm_hdl_read(s2_hier, s2_val));
        `uvm_info(get_type_name(),
            "  [GATE_HDL_SKIP] cal_done_s1/s2 backdoor skipped in gate sim (CAL_CTRL[1] frontdoor already PASS)", UVM_LOW)
`else
        void'(uvm_hdl_read(s1_hier, s1_val));
        void'(uvm_hdl_read(s2_hier, s2_val));
        `uvm_info(get_type_name(),
            $sformatf("  cal_done_s1=%0d cal_done_s2=%0d (both should be 1)", s1_val, s2_val), UVM_LOW)
        if (s1_val && s2_val) begin
            `uvm_info(get_type_name(),
                "[PASS] CAL_DONE_SYNC: sync chain cal_done_s1/s2 both 1 (level follow)", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(),
                $sformatf("[FAIL] CAL_DONE_SYNC: sync chain not both 1 (s1=%0d s2=%0d)", s1_val, s2_val))
        end
`endif
        // Clear CAL_ST=0 → cal_done drops → s1 then s2 clear after 2 PCLK
        apb_write(`ADC_CAL_CTRL, 32'h0000_0000);
        #100;  // 1 PCLK ≈ 20ns, wait ~5 PCLK for 2-stage clear
        void'(uvm_hdl_read(s1_hier, s1_val));
        `uvm_info(get_type_name(),
            $sformatf("  After CAL_ST=0, +100ns: cal_done_s1=%0d (may be clearing)", s1_val), UVM_LOW)
        #500;  // total ~600ns — well past 2 PCLK sync
        apb_read(`ADC_CAL_CTRL, rd);
        void'(uvm_hdl_read(s1_hier, s1_val));
        void'(uvm_hdl_read(s2_hier, s2_val));
        if (!rd[1] && !s2_val) begin
            `uvm_info(get_type_name(),
                $sformatf("[PASS] CAL_DONE_SYNC: CAL_CTRL[1]=0 after CAL_ST=0 (s1=%0d s2=%0d cleared)", s1_val, s2_val), UVM_LOW)
        end else begin
            `uvm_error(get_type_name(),
                $sformatf("[FAIL] CAL_DONE_SYNC: CAL_CTRL[1]=%0d after CAL_ST=0 (s1=%0d s2=%0d)", rd[1], s1_val, s2_val))
        end
    endtask

    // ────────────────────────────────────────────────────────────────────────
    // CAL_NO_TIMEOUT: controller implements no timeout protection. If CAL_DONE
    //   never returns, software can detect via CAL_BUSY (STAT[3]) staying 1.
    //   Analog model auto-completes, so we verify the observable behavior:
    //   CAL_BUSY=1 during cal, =0 after completion (normal path). Software
    //   could detect a stuck-cal by polling CAL_BUSY and timing out.
    // ────────────────────────────────────────────────────────────────────────
    task cal_no_timeout();
        bit [31:0] rd;
        bit busy_during, busy_after;
        `uvm_info(get_type_name(), "=== CAL_NO_TIMEOUT: no hw timeout (CAL_BUSY behavior) ===", UVM_LOW)
        apb_write(`ADC_CTRL, 32'h0000_0002); #2000;  // SW_RST
        apb_write(`ADC_CTRL, 32'h0000_0001); #200;   // ADC_EN=1
        apb_write(`ADC_CAL_CTRL, 32'h0000_0001);  // CAL_ST=1
        #200;
        apb_read(`ADC_STAT, rd);
        busy_during = rd[3];
        // Wait for normal completion
        wait_cal_done(50);
        #500;  // cal_busy_s2 clears
        apb_read(`ADC_STAT, rd);
        busy_after = rd[3];
        `uvm_info(get_type_name(),
            $sformatf("  CAL_BUSY during cal=%0d, after cal=%0d", busy_during, busy_after), UVM_LOW)
        if (busy_during && !busy_after) begin
            `uvm_info(get_type_name(),
                "[PASS] CAL_NO_TIMEOUT: CAL_BUSY=1 during cal, =0 after (software can poll to detect stuck)", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(),
                $sformatf("[FAIL] CAL_NO_TIMEOUT: busy_during=%0d busy_after=%0d", busy_during, busy_after))
        end
        apb_write(`ADC_CAL_CTRL, 32'h0000_0000);
        #500;
    endtask
endclass
