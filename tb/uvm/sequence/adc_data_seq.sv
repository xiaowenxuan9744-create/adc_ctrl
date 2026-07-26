// ============================================================================
// Sequence: adc_data_seq
// Description: Data path test sequence
//              DATA_001: VALID read-clear
//              DATA_002: Data alignment (right/left)
//              DATA_003: OVERFLOW detection
//              REG_CH_DATA_VALID (旧 REG_007): VALID 1→0 + ADC_CLK 域 VALID 清零
//              SMP_PRECISION_14BIT: 14-bit ADC full-range (0x0000 / 0x3FFF)
// ============================================================================

class adc_data_seq extends adc_base_seq;
    `uvm_object_utils(adc_data_seq)

    function new(string name = "adc_data_seq");
        super.new(name);
    endfunction

    task body();
        bit [31:0] rd, rd2;
        bit [31:0] adc_valid_bit;
        bit [31:0] pclk_valid_bit;
        integer n;

        `uvm_info(get_type_name(), "=== Data Path Test ===", UVM_LOW)
        #300;

        // SW_RST for clean CDC state
        apb_write(`ADC_CTRL, 32'h0000_0002);
        #2000;
        apb_write(`ADC_CTRL, 32'h0000_0001);
        #200;
        #300;

        // Enable ADC
        apb_write(`ADC_CTRL, 32'h0000_0001);
        #200;

        // --- DATA_001: VALID read-clear ---
        write_lp_seq_single(5'h00);  // sets LP_SEQ_LEN=1
        apb_write(`ADC_TRIG, 32'h0000_0002);
        apb_write(`ADC_TRIG, 32'h0000_0003);
        #5000;

        // First read — VALID should be 1
        apb_read(`ADC_LP_DATA0, rd);
        if (rd[31]) begin
            `uvm_info(get_type_name(), $sformatf("[PASS] DATA_001: First read VALID=1 data=0x%04h", rd[15:0]), UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), "[FAIL] DATA_001: First read VALID=0")
        end

        // Second read — VALID should be 0 (read-clear)
        #200;  // Wait for CDC round-trip
        apb_read(`ADC_LP_DATA0, rd2);
        if (!rd2[31]) begin
            `uvm_info(get_type_name(), "[PASS] DATA_001: Second read VALID=0 (read-clear)", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), "[FAIL] DATA_001: Second read VALID=1 (not cleared)")
        end

        // --- DATA_002: Data alignment ---
        // Right-aligned mode (default)
        apb_write(`ADC_CTRL, 32'h0000_0001);  // DATA_ALIGN=00
        #200;
        write_lp_seq_single(5'h00);  // sets LP_SEQ_LEN=1
        apb_write(`ADC_TRIG, 32'h0000_0002);
        apb_write(`ADC_TRIG, 32'h0000_0003);
        #5000;
        apb_read(`ADC_LP_DATA0, rd);
        `uvm_info(get_type_name(), $sformatf("  Right-aligned data: 0x%04h", rd[15:0]), UVM_LOW)

        // Left-aligned mode: DATA_ALIGN=bit[3]=1, ADC_EN=bit[0]=1
        // Use SW_RST to clear LP_DATA[0] VALID so the next sample doesn't
        // overflow on slot 0 (read-clear would also work, but SW_RST is
        // simpler and avoids CDC round-trip timing).
        apb_write(`ADC_CTRL, 32'h0000_0002); #2000;  // SW_RST
        apb_write(`ADC_CTRL, 32'h0000_0009);  // bit[3]=1 → left-align, bit[0]=1 → en
        #200;
        write_lp_seq_single(5'h00);  // sets LP_SEQ_LEN=1
        apb_write(`ADC_TRIG, 32'h0000_0002);
        apb_write(`ADC_TRIG, 32'h0000_0003);
        #5000;
        apb_read(`ADC_LP_DATA0, rd2);
        `uvm_info(get_type_name(), $sformatf("  Left-aligned data: 0x%04h", rd2[15:0]), UVM_LOW)

        // Verify data is in different bit positions
        if (rd != rd2) begin
            `uvm_info(get_type_name(), "[PASS] DATA_002: Alignment modes produce different data", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), "[FAIL] DATA_002: Both alignment modes return same data")
        end

        // --- DATA_003: OVERFLOW ---
        // Enable OVERRUN interrupt + LP_EOC interrupt.
        // SW_RST first to clear any leftover VALID on slot 0 from DATA_002,
        // otherwise the very first trigger below would OVERRUN before we
        // establish the "first sample VALID=1" baseline.
        apb_write(`ADC_CTRL, 32'h0000_0002);  // SW_RST
        #2000;
        apb_write(`ADC_CTRL, 32'h0000_0001);  // ADC_EN=1, right-align
        #200;
        apb_write(`ADC_INT_EN, 32'h0000_0021);  // INT_EN[5]=OVERRUN_EN, INT_EN[0]=LP_EOC_EN
        #100;
        // Sample LP slot 0 twice without reading. LP_SEQ_LEN=1 forces exactly
        // one sample per trigger → slot 0 written each time.
        write_lp_seq_single(5'h05);  // LP slot 0 = CH5
        apb_write(`ADC_LP_SEQ_LEN, 32'h0000_0001);  // 1-entry sequence → slot 0
        apb_write(`ADC_TRIG, 32'h0000_0002);
        apb_write(`ADC_TRIG, 32'h0000_0003);
        #8000;  // Wait for 1-entry sequence; slot 0 VALID=1 now
        // Don't read — sample again on the same slot 0 → overflow
        apb_write(`ADC_TRIG, 32'h0000_0002);
        apb_write(`ADC_TRIG, 32'h0000_0003);
        #10000;  // Wait for second 1-entry sequence + OVERRUN CDC into INT_STAT

        // Check INT_STAT for OVERRUN
        apb_read(`ADC_INT_STAT, rd);  // INT_STAT
        if (rd[5]) begin
            `uvm_info(get_type_name(), "[PASS] DATA_003: OVERRUN interrupt asserted", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), "[FAIL] DATA_003: No OVERRUN interrupt")
        end
        // INT_009: Both OVERRUN and LP_EOC should be set simultaneously
        if (rd[0]) begin
            `uvm_info(get_type_name(), "[PASS] INT_009: LP_EOC also asserted with OVERRUN (same cycle)", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), "[FAIL] INT_009: LP_EOC not asserted with OVERRUN")
        end

        // Read LP slot 0 (write_lp_seq_single(5'h05) puts CH5 in ENT0 = slot 0)
        apb_read(`ADC_LP_DATA0 + 0*4, rd);
        `uvm_info(get_type_name(), $sformatf("  LP_DATA[0] (CH5) = 0x%08h", rd), UVM_LOW)
        if (rd[31]) begin
            `uvm_info(get_type_name(), $sformatf("[PASS] DATA_003: New data after overflow (0x%08h)", rd), UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), $sformatf("[FAIL] DATA_003: No new data (0x%08h)", rd))
        end

        // ----------------------------------------------------------------------
        // REG_SEQ_DATA_VALID (旧 REG_007): VALID 1→0 + PCLK 域 VALID 清零
        //   验证采样后读 LP_DATA[slot] VALID=1，再读 VALID=0（PCLK 域
        //   lp_valid_pclk[slot] 本地清零）；再用 uvm_hdl_read 读 PCLK 域
        //   lp_valid_pclk[slot] 寄存器确认清零。新架构下 VALID 完全在 PCLK
        //   域管理（无需 ADC_CLK 回传清零）。
        // ----------------------------------------------------------------------
        `uvm_info(get_type_name(), "=== REG_SEQ_DATA_VALID (旧 REG_007) ===", UVM_LOW)
        begin
            // Sample LP slot 0 (write_lp_seq_single puts ch in ENT0).
            integer slot;
            string   pclk_hier;
            bit      pclk_valid_val;

            slot = 0;
            pclk_hier = $sformatf("tb_top.u_dut.u_regfile.gen_active.lp_valid_pclk[%0d]", slot);

            // SW_RST to clean slate
            apb_write(`ADC_CTRL, 32'h0000_0002);  // SW_RST=1
            #2000;
            apb_write(`ADC_CTRL, 32'h0000_0001);  // ADC_EN=1
            #200;
            apb_write(`ADC_INT_EN, 32'h0000_0001);  // LP_EOC_EN to get event
            #100;

            // Sample LP slot 0 (channel 10 to avoid interference)
            write_lp_seq_single(5'd10);  // sets LP_SEQ_LEN=1
            apb_write(`ADC_TRIG, 32'h0000_0002);
            apb_write(`ADC_TRIG, 32'h0000_0003);
            #8000;  // wait for 1-entry LP sequence + LP_EOC

            // First read: VALID should be 1 (PCLK domain read-clear)
            apb_read(`ADC_LP_DATA0 + slot*4, rd);
            if (rd[31]) begin
                `uvm_info(get_type_name(),
                    $sformatf("[PASS] REG_SEQ_DATA_VALID: slot %0d first read VALID=1 data=0x%04h", slot, rd[15:0]), UVM_LOW)
            end else begin
                `uvm_error(get_type_name(),
                    $sformatf("[FAIL] REG_SEQ_DATA_VALID: slot %0d first read VALID=0 (expected 1)", slot))
            end

            // Second read: VALID should be 0 (PCLK read-clear worked)
            #200;
            apb_read(`ADC_LP_DATA0 + slot*4, rd2);
            if (!rd2[31]) begin
                `uvm_info(get_type_name(),
                    "[PASS] REG_SEQ_DATA_VALID: second read VALID=0 (PCLK read-clear)", UVM_LOW)
            end else begin
                `uvm_error(get_type_name(),
                    "[FAIL] REG_SEQ_DATA_VALID: second read VALID=1 (PCLK read-clear failed)")
            end

            // Backdoor check: PCLK domain lp_valid_pclk[slot] must be 0
            #500;
            // GATE_SIM guard: uvm_hdl_read on RTL-internal path returns 0 (path
            // not found in gate netlist — gen_active renamed). Skip backdoor
            // assertion in gate sim; frontdoor read-clear (above) already
            // validated the behavior. RTL sim still runs the full check.
`ifdef GATE_SIM
            void'(uvm_hdl_read(pclk_hier, pclk_valid_val));
            `uvm_info(get_type_name(),
                $sformatf("  [GATE_HDL_SKIP] PCLK lp_valid_pclk[%0d] backdoor skipped in gate sim (frontdoor read-clear already PASS)", slot), UVM_LOW)
`else
            void'(uvm_hdl_read(pclk_hier, pclk_valid_val));
            if (pclk_valid_val == 1'b0) begin
                `uvm_info(get_type_name(),
                    $sformatf("[PASS] REG_SEQ_DATA_VALID: PCLK lp_valid_pclk[%0d]=0 cleared", slot), UVM_LOW)
            end else begin
                `uvm_error(get_type_name(),
                    $sformatf("[FAIL] REG_SEQ_DATA_VALID: PCLK lp_valid_pclk[%0d]=1 (not cleared)", slot))
            end
`endif
        end

        // --- SMP_PRECISION_14BIT: 14-bit ADC full-range boundary ---
        smp_precision_14bit();

        `uvm_info(get_type_name(), "Data path test complete", UVM_LOW)
    endtask

    // ────────────────────────────────────────────────────────────────────────
    // SMP_PRECISION_14BIT: 14-bit ADC 精度，adc_data[13:0] 全量程。
    //   ovrd_enable(0x3FFF) → sample → DATA[13:0]=0x3FFF (full scale)
    //   ovrd_enable(0x0000) → sample → DATA[13:0]=0x0000 (zero scale)
    //   Right-aligned mode: DATA = {2'b00, adc_data[13:0]}
    // ────────────────────────────────────────────────────────────────────────
    task smp_precision_14bit();
        bit [31:0] rd;
        `uvm_info(get_type_name(), "=== SMP_PRECISION_14BIT: full-range 14-bit ===", UVM_LOW)
        // SW_RST for clean slate
        apb_write(`ADC_CTRL, 32'h0000_0002); #2000;
        apb_write(`ADC_CTRL, 32'h0000_0001);  // ADC_EN=1, right-align
        #200;

        // Full-scale: adc_data = 0x3FFF
        ovrd_enable(14'h3FFF);
        #200;
        write_lp_seq_single(5'h02);  // CH2 (not used above); sets LP_SEQ_LEN=1
        apb_write(`ADC_TRIG, 32'h0000_0002);
        apb_write(`ADC_TRIG, 32'h0000_0003);
        #8000;  // wait for 1-entry sequence + EOC + CDC
        apb_read(`ADC_LP_DATA0 + 0*4, rd);  // LP slot 0 (CH2)
        if (rd[31] && rd[13:0] == 14'h3FFF) begin
            `uvm_info(get_type_name(),
                $sformatf("[PASS] SMP_PRECISION_14BIT: full-scale DATA=0x%04h (VALID=1)", rd[15:0]), UVM_LOW)
        end else begin
            `uvm_error(get_type_name(),
                $sformatf("[FAIL] SMP_PRECISION_14BIT: full-scale DATA=0x%04h (exp 0x3FFF, VALID=%0d)",
                    rd[15:0], rd[31]))
        end

        // Zero-scale: adc_data = 0x0000
        // SW_RST to clear CH2 VALID (read-clear only clears on read; fresh
        // sample would set VALID again but overflow_event may fire. Use SW_RST.)
        apb_write(`ADC_CTRL, 32'h0000_0002); #2000;
        apb_write(`ADC_CTRL, 32'h0000_0001); #200;
        ovrd_enable(14'h0000);
        #200;
        write_lp_seq_single(5'h03);  // CH3; sets LP_SEQ_LEN=1
        apb_write(`ADC_TRIG, 32'h0000_0002);
        apb_write(`ADC_TRIG, 32'h0000_0003);
        #8000;
        apb_read(`ADC_LP_DATA0 + 0*4, rd);  // LP slot 0 (CH3)
        if (rd[31] && rd[13:0] == 14'h0000) begin
            `uvm_info(get_type_name(),
                $sformatf("[PASS] SMP_PRECISION_14BIT: zero-scale DATA=0x%04h (VALID=1)", rd[15:0]), UVM_LOW)
        end else begin
            `uvm_error(get_type_name(),
                $sformatf("[FAIL] SMP_PRECISION_14BIT: zero-scale DATA=0x%04h (exp 0x0000, VALID=%0d)",
                    rd[15:0], rd[31]))
        end

        ovrd_disable();
    endtask

    task write_lp_seq_single(bit [4:0] ch);
        apb_write(`ADC_LP_SEQ0, {24'h000000, ch});
        apb_write(`ADC_LP_SEQ1, 32'h00000000);
        apb_write(`ADC_LP_SEQ2, 32'h00000000);
        apb_write(`ADC_LP_SEQ3, 32'h00000000);
        apb_write(`ADC_LP_SEQ4, 32'h00000000);
        apb_write(`ADC_LP_SEQ5, 32'h00000000);
        apb_write(`ADC_LP_SEQ6, 32'h00000000);
        apb_write(`ADC_LP_SEQ7, 32'h00000000);
    endtask
endclass
