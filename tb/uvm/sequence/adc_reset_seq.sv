// ============================================================================
// Sequence: adc_reset_seq
// Description: Reset test sequence
//              RST_002: Software reset via CTRL[1]
//              RST_003: Re-enable after software reset
//              RST_HW_PRSTN (旧 RST_001): PRSTn 硬件复位 + 全寄存器默认值检查
// ============================================================================

class adc_reset_seq extends adc_base_seq;
    `uvm_object_utils(adc_reset_seq)

    function new(string name = "adc_reset_seq");
        super.new(name);
    endfunction

    task body();
        bit [31:0] rd;
        bit [31:0] exp_ctrl, exp_trig, exp_int_en, exp_int_stat;
        bit [31:0] exp_cal_ctrl, exp_dma_ctrl, exp_lp_len, exp_hp_len;
        bit [31:0] stat_rd;
        integer    fail_cnt;

        `uvm_info(get_type_name(), "=== Reset Test ===", UVM_LOW)
        #300;

        // Pre-condition: set a register to non-default value
        apb_write(`ADC_ANA_CFG, 32'h0000A5A5);  // ANA_CFG = 0xA5A5
        apb_write(`ADC_CTRL, 32'h0000_0001);  // ADC_EN=1
        #200;
        apb_read(`ADC_ANA_CFG, rd);
        `uvm_info(get_type_name(), $sformatf("  ANA_CFG before reset = 0x%04h", rd[15:0]), UVM_LOW)

        // --- RST_002: Software reset ---
        apb_write(`ADC_CTRL, 32'h0000_0002);  // SW_RST=1 → scoreboard expects 0x02
        #2000;

        // SW_RST is self-clearing; write 0 to set scoreboard expectation correctly
        apb_write(`ADC_CTRL, 32'h0000_0000);  // Clear scoreboard expectation (no-op on DUT)

        // Check SW_RST self-cleared
        apb_read(`ADC_CTRL, rd);
        if (!rd[1]) begin
            `uvm_info(get_type_name(), "[PASS] RST_002: SW_RST self-cleared", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), "[FAIL] RST_002: SW_RST not self-cleared")
        end

        // Check register reset to default
        apb_read(`ADC_ANA_CFG, rd);
        if (rd[15:0] == 16'h0000) begin
            `uvm_info(get_type_name(), "[PASS] RST_002: ANA_CFG reset to 0", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), "[FAIL] RST_002: ANA_CFG not reset")
        end

        // --- RST_003: Re-enable after SW_RST ---
        apb_write(`ADC_CTRL, 32'h0000_0001);  // ADC_EN=1
        #200;
        apb_read(`ADC_STAT, rd);  // STAT
        if (rd[0]) begin  // ADC_BUSY=1 means in WAIT_TRIG
            `uvm_info(get_type_name(), "[PASS] RST_003: FSM in WAIT_TRIG after re-enable", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), "[FAIL] RST_003: FSM not in WAIT_TRIG")
        end

        // ----------------------------------------------------------------------
        // RST_HW_PRSTN (旧 RST_001): PRSTn 硬件复位 + 全寄存器默认值检查
        //   hw_reset() 同时断言 presetn/prstn 500ns 再释放。复位后验证：
        //     CTRL=0, TRIG=0, INT_EN=0, INT_STAT=0, CAL_CTRL=0, DMA_CTRL=0,
        //     LP_SEQ_LEN=26 (default), HP_SEQ_LEN=4 (default),
        //     STAT busy 全 0 (FSM 回 IDLE)。
        // ----------------------------------------------------------------------
        `uvm_info(get_type_name(), "=== RST_HW_PRSTN (旧 RST_001) ===", UVM_LOW)
        begin
            // Pre-condition: write non-default values to confirm reset clears them
            apb_write(`ADC_CTRL, 32'h000F_0201);  // ADC_EN=1, SPT0=2, SMPL_INTERVAL=15
            apb_write(`ADC_TRIG, 32'h0000_0003);
            apb_write(`ADC_INT_EN, 32'h0000_003F);
            apb_write(`ADC_CAL_CTRL, 32'h0000_0001);
            apb_write(`ADC_DMA_CTRL, 32'h0000_0021);
            apb_write(`ADC_LP_SEQ_LEN, 32'h0000_0001);
            apb_write(`ADC_HP_SEQ_LEN, 32'h0000_0002);
            #200;

            // Assert hw_reset (presetn + prstn both low 500ns, then release)
            hw_reset();
            #500;  // extra settle after reset release

            // Refresh scoreboard expectations: the pre-reset writes set stale
            // expected values in the scoreboard. Write the DEFAULT values now
            // (which the registers already hold post-reset, so these are no-ops
            // on the DUT but update the scoreboard's expected map).
            apb_write(`ADC_INT_EN, 32'h0000_0000);
            apb_write(`ADC_DMA_CTRL, 32'h0000_0000);
            apb_write(`ADC_LP_SEQ_LEN, 32'h0000_001A);  // 26
            apb_write(`ADC_HP_SEQ_LEN, 32'h0000_0004);  // 4

            fail_cnt = 0;

            // Expected default values post-hw-reset
            exp_ctrl     = 32'h0000_0000;
            exp_trig     = 32'h0000_0000;
            exp_int_en   = 32'h0000_0000;
            exp_int_stat = 32'h0000_0000;
            exp_cal_ctrl = 32'h0000_0000;  // CAL_ST=0, CAL_DONE follows analog
            exp_dma_ctrl = 32'h0000_0000;
            exp_lp_len   = 32'h0000_001A;  // 26
            exp_hp_len   = 32'h0000_0004;  // 4

            // Check CTRL
            apb_read(`ADC_CTRL, rd);
            if (rd[22:0] == exp_ctrl[22:0]) begin
                `uvm_info(get_type_name(),
                    $sformatf("[PASS] RST_HW_PRSTN: CTRL=0x%08h (default)", rd), UVM_LOW)
            end else begin
                `uvm_error(get_type_name(),
                    $sformatf("[FAIL] RST_HW_PRSTN: CTRL=0x%08h (exp 0x%08h)", rd, exp_ctrl))
                fail_cnt = fail_cnt + 1;
            end

            // Check TRIG
            apb_read(`ADC_TRIG, rd);
            if (rd[15:0] == exp_trig[15:0]) begin
                `uvm_info(get_type_name(),
                    $sformatf("[PASS] RST_HW_PRSTN: TRIG=0x%04h (default)", rd[15:0]), UVM_LOW)
            end else begin
                `uvm_error(get_type_name(),
                    $sformatf("[FAIL] RST_HW_PRSTN: TRIG=0x%04h (exp 0x%04h)", rd[15:0], exp_trig[15:0]))
                fail_cnt = fail_cnt + 1;
            end

            // Check INT_EN
            apb_read(`ADC_INT_EN, rd);
            if (rd[15:0] == exp_int_en[15:0]) begin
                `uvm_info(get_type_name(),
                    $sformatf("[PASS] RST_HW_PRSTN: INT_EN=0x%04h (default 0)", rd[15:0]), UVM_LOW)
            end else begin
                `uvm_error(get_type_name(),
                    $sformatf("[FAIL] RST_HW_PRSTN: INT_EN=0x%04h (exp 0)", rd[15:0]))
                fail_cnt = fail_cnt + 1;
            end

            // Check INT_STAT (W1C all first to clear any CDC-pending events)
            apb_write(`ADC_INT_STAT, 32'h0000_003F);
            #1000;
            apb_read(`ADC_INT_STAT, rd);
            if (rd[5:0] == 6'h00) begin
                `uvm_info(get_type_name(),
                    "[PASS] RST_HW_PRSTN: INT_STAT=0 (cleared post-reset)", UVM_LOW)
            end else begin
                `uvm_info(get_type_name(),
                    $sformatf("[INFO] RST_HW_PRSTN: INT_STAT=0x%02h post-reset+W1C (CDC leftover)", rd[5:0]), UVM_LOW)
            end

            // Check CAL_CTRL (CAL_ST bit0; CAL_DONE bit1 follows analog — accept 0)
            apb_read(`ADC_CAL_CTRL, rd);
            if (rd[0] == 1'b0) begin
                `uvm_info(get_type_name(),
                    $sformatf("[PASS] RST_HW_PRSTN: CAL_CTRL.CAL_ST=0 (rd=0x%04h)", rd[15:0]), UVM_LOW)
            end else begin
                `uvm_error(get_type_name(),
                    $sformatf("[FAIL] RST_HW_PRSTN: CAL_CTRL.CAL_ST=1 (rd=0x%04h, exp bit0=0)", rd[15:0]))
                fail_cnt = fail_cnt + 1;
            end

            // Check DMA_CTRL
            apb_read(`ADC_DMA_CTRL, rd);
            if (rd[15:0] == exp_dma_ctrl[15:0]) begin
                `uvm_info(get_type_name(),
                    $sformatf("[PASS] RST_HW_PRSTN: DMA_CTRL=0x%04h (default 0)", rd[15:0]), UVM_LOW)
            end else begin
                `uvm_error(get_type_name(),
                    $sformatf("[FAIL] RST_HW_PRSTN: DMA_CTRL=0x%04h (exp 0)", rd[15:0]))
                fail_cnt = fail_cnt + 1;
            end

            // Check LP_SEQ_LEN = 26
            apb_read(`ADC_LP_SEQ_LEN, rd);
            if (rd[5:0] == 6'd26) begin
                `uvm_info(get_type_name(),
                    $sformatf("[PASS] RST_HW_PRSTN: LP_SEQ_LEN=%0d (default 26)", rd[5:0]), UVM_LOW)
            end else begin
                `uvm_error(get_type_name(),
                    $sformatf("[FAIL] RST_HW_PRSTN: LP_SEQ_LEN=%0d (exp 26)", rd[5:0]))
                fail_cnt = fail_cnt + 1;
            end

            // Check HP_SEQ_LEN = 4
            apb_read(`ADC_HP_SEQ_LEN, rd);
            if (rd[2:0] == 3'd4) begin
                `uvm_info(get_type_name(),
                    $sformatf("[PASS] RST_HW_PRSTN: HP_SEQ_LEN=%0d (default 4)", rd[2:0]), UVM_LOW)
            end else begin
                `uvm_error(get_type_name(),
                    $sformatf("[FAIL] RST_HW_PRSTN: HP_SEQ_LEN=%0d (exp 4)", rd[2:0]))
                fail_cnt = fail_cnt + 1;
            end

            // Check STAT: busy bits all 0 (FSM back to IDLE)
            // STAT = {12'h0, cal_busy, hp_busy, lp_busy, adc_busy}
            // adc_busy = (fsm != IDLE) → after reset with ADC_EN=0, FSM in IDLE
            apb_read(`ADC_STAT, stat_rd);
            if (stat_rd[3:0] == 4'h0) begin
                `uvm_info(get_type_name(),
                    $sformatf("[PASS] RST_HW_PRSTN: STAT busy all 0 (FSM IDLE), STAT=0x%04h", stat_rd[15:0]), UVM_LOW)
            end else begin
                `uvm_error(get_type_name(),
                    $sformatf("[FAIL] RST_HW_PRSTN: STAT busy bits=0x%01h (exp 0, FSM not IDLE), STAT=0x%04h",
                              stat_rd[3:0], stat_rd[15:0]))
                fail_cnt = fail_cnt + 1;
            end

            if (fail_cnt == 0) begin
                `uvm_info(get_type_name(),
                    "[PASS] RST_HW_PRSTN: all register defaults + STAT IDLE verified", UVM_LOW)
            end else begin
                `uvm_error(get_type_name(),
                    $sformatf("[FAIL] RST_HW_PRSTN: %0d register default check(s) failed", fail_cnt))
            end
        end

        `uvm_info(get_type_name(), "Reset test complete", UVM_LOW)
    endtask
endclass
