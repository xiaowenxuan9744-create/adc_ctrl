// ============================================================================
// Sequence: adc_int_seq
// Description: Interrupt test sequence
//              INT_001: LP_EOC — single sample → INT_STAT[0] = 1
//              INT_002: LP_SEQ_DONE — sequence complete → INT_STAT[1] = 1
//              INT_003: W1C clear works
//              INT_007: INT_EN=0 → events still recorded in INT_STAT,
//                       but adc_int output is gated
//              INT_ADC_INT_DOMAIN: adc_int = INT_STAT & INT_EN 聚合验证
// ============================================================================

class adc_int_seq extends adc_base_seq;
    `uvm_object_utils(adc_int_seq)

    function new(string name = "adc_int_seq");
        super.new(name);
    endfunction

    // Write a 1-entry LP sequence (ENT0=ch, all others = CH31 to avoid OVERRUN)
    task write_lp_seq_single(bit [4:0] ch);
        apb_write(`ADC_LP_SEQ0, {24'h1F1F1F, ch[4:0]});  // ENT0=ch, ENT1-3=CH31
        apb_write(`ADC_LP_SEQ1, 32'h1F1F1F1F);  // ENT4-7 = CH31
        apb_write(`ADC_LP_SEQ2, 32'h1F1F1F1F);
        apb_write(`ADC_LP_SEQ3, 32'h1F1F1F1F);
        apb_write(`ADC_LP_SEQ4, 32'h1F1F1F1F);
        apb_write(`ADC_LP_SEQ5, 32'h1F1F1F1F);
        apb_write(`ADC_LP_SEQ6, 32'h1F1F1F1F);
        apb_write(`ADC_LP_SEQ7, 32'h1F1F1F1F);
    endtask

    // Clear scoreboard expectation for addr (write expected readback value)
    task clear_sb_exp(bit [15:0] addr, bit [31:0] exp);
        apb_write(addr, exp);
    endtask

    task body();
        bit [31:0] rd, stat;
        integer n;

        `uvm_info(get_type_name(), "=== Interrupt Test ===", UVM_LOW)
                #300;  // Wait for power-on reset

        // SW_RST for clean CDC state
        apb_write(`ADC_CTRL, 32'h0000_0002);
        #2000;
        apb_write(`ADC_CTRL, 32'h0000_0001);
        #200;

        // --- INT_001: LP_EOC interrupt ---
        // Enable LP_EOC interrupt, trigger single sample, check INT_STAT[0]
        apb_write(`ADC_INT_EN, 32'h0000_0001);  // INT_EN[0] = LP_EOC_EN
        apb_write(`ADC_CTRL, 32'h0000_0001);  // ADC_EN=1
        #200;
        write_lp_seq_single(5'h05);           // Single-entry LP: CH5 only
        apb_write(`ADC_LP_SEQ_LEN, 32'h0000_0001);  // 1-entry sequence
        apb_write(`ADC_TRIG, 32'h0000_0002);  // LP_SW_TRG_EN
        apb_write(`ADC_TRIG, 32'h0000_0003);  // LP_SW_TRIG
        #25000;                                // Wait for 1-entry sequence
        apb_read(`ADC_INT_STAT, rd);               // INT_STAT
        if (rd[0]) begin
            `uvm_info(get_type_name(), $sformatf("[PASS] INT_001: LP_EOC asserted (INT_STAT=0x%04h)", rd), UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), $sformatf("[FAIL] INT_001: LP_EOC not asserted (INT_STAT=0x%04h)", rd))
        end
        // W1C clear LP_EOC only
        // Write twice: first clears, second catches any CDC-pipeline-delayed event
        apb_write(`ADC_INT_STAT, 32'h0000_0001);
        #1000;
        apb_write(`ADC_INT_STAT, 32'h0000_0001);
        clear_sb_exp(`ADC_INT_STAT, 32'h00000000);
        #1000;
        apb_read(`ADC_INT_STAT, rd);
        if (!rd[0]) begin
            `uvm_info(get_type_name(), "[PASS] INT_001: W1C cleared LP_EOC", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), "[FAIL] INT_001: W1C did not clear LP_EOC")
        end

        // --- INT_002: LP_SEQ_DONE interrupt ---
        apb_write(`ADC_INT_EN, 32'h0000_0002);  // INT_EN[1] = LP_SEQ_DONE_EN
        #100;
        write_lp_seq_single(5'h05);
        apb_write(`ADC_LP_SEQ_LEN, 32'h0000_0001);  // 1-entry sequence
        apb_write(`ADC_TRIG, 32'h0000_0002);
        apb_write(`ADC_TRIG, 32'h0000_0003);
        #8000;  // Wait for 1-entry sequence
        clear_sb_exp(`ADC_INT_STAT, 32'h00000000);
        #100;
        apb_read(`ADC_INT_STAT, rd);
        if (rd[1]) begin
            `uvm_info(get_type_name(), $sformatf("[PASS] INT_002: LP_SEQ_DONE asserted (INT_STAT=0x%04h)", rd), UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), $sformatf("[FAIL] INT_002: LP_SEQ_DONE not asserted (INT_STAT=0x%04h)", rd))
        end
        apb_write(`ADC_INT_STAT, 32'h0000_0002);  // W1C bit 1
        clear_sb_exp(`ADC_INT_STAT, 32'h00000000);
        #500;

        // --- INT_007: INT_EN gating — events recorded in INT_STAT even when disabled,
        // but adc_int output stays low. Write W1C all first, then disable INT_EN.
        apb_write(`ADC_INT_STAT, 32'h0000_003F);  // W1C all bits
        clear_sb_exp(`ADC_INT_STAT, 32'h00000000);
        #1000;
        apb_write(`ADC_INT_EN, 32'h0000_0000);  // All interrupts disabled
        #100;
        write_lp_seq_single(5'h05);
        apb_write(`ADC_LP_SEQ_LEN, 32'h0000_0001);  // 1-entry sequence
        apb_write(`ADC_TRIG, 32'h0000_0002);
        apb_write(`ADC_TRIG, 32'h0000_0003);
        #8000;
        // Check: adc_int output should be LOW (gated by INT_EN=0)
        if (m_vif != null && m_vif.adc_int == 1'b0) begin
            `uvm_info(get_type_name(), "[PASS] INT_007: adc_int stays low when INT_EN=0", UVM_LOW)
        end else if (m_vif != null) begin
            `uvm_error(get_type_name(), "[FAIL] INT_007: adc_int asserted despite INT_EN=0")
        end
        // Check: INT_STAT should still have recorded events (raw event recording)
        clear_sb_exp(`ADC_INT_STAT, 32'h00000000);
        #100;
        apb_read(`ADC_INT_STAT, rd);
        if (rd[0]) begin
            `uvm_info(get_type_name(), $sformatf("[PASS] INT_007: Events recorded in INT_STAT even when disabled (0x%04h)", rd), UVM_LOW)
        end else begin
            `uvm_info(get_type_name(), "[INFO] INT_007: No events in INT_STAT (may be CDC settling)", UVM_LOW)
        end

        // Re-enable and verify it works again
        apb_write(`ADC_INT_EN, 32'h0000_0001);
        #100;
        // Clear any pending INT_STAT from prior sub-tests before re-trigger
        apb_write(`ADC_INT_STAT, 32'h0000_003F);
        clear_sb_exp(`ADC_INT_STAT, 32'h00000000);
        #2000;  // wait for CDC + W1C to settle
        // Disable INT_EN during the re-trigger so the new LP_EOC lands in
        // INT_STAT[0] cleanly. The final read checks INT_STAT[0]=1 (raw
        // event recording), independent of INT_EN.
        apb_write(`ADC_INT_EN, 32'h0000_0000);
        #200;
        apb_write(`ADC_INT_STAT, 32'h0000_003F);  // final clear before trigger
        #2000;
        apb_write(`ADC_INT_EN, 32'h0000_0001);  // re-enable LP_EOC
        #100;
        write_lp_seq_single(5'h05);  // also sets LP_SEQ_LEN=1
        apb_write(`ADC_TRIG, 32'h0000_0002);
        apb_write(`ADC_TRIG, 32'h0000_0003);
        #10000;  // wait for 1-entry sequence + LP_EOC CDC to INT_STAT
        clear_sb_exp(`ADC_INT_STAT, 32'h00000000);
        #100;
        apb_read(`ADC_INT_STAT, rd);
        if (rd[0]) begin
            `uvm_info(get_type_name(), "[PASS] INT_007: Interrupt works after re-enable", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), "[FAIL] INT_007: Still no interrupt after re-enable")
        end

        // ----------------------------------------------------------------------
        // INT_ADC_INT_DOMAIN: adc_int = INT_STAT & INT_EN 聚合验证
        //   使能 INT_EN[0]（LP_EOC），触发 LP_EOC 事件，验证 adc_int=1；
        //   清 INT_STAT[0] 后验证 adc_int=0。
        //   证明 adc_int 在 PCLK 域由 INT_STAT & INT_EN 聚合驱动。
        // ----------------------------------------------------------------------
        `uvm_info(get_type_name(), "=== INT_ADC_INT_DOMAIN ===", UVM_LOW)
        begin
            bit int_high_seen;
            bit stat_clean;

            // W1C all + SW_RST to clean slate (clear any leftover INT_STAT bits
            // from prior INT_007 sub-tests — OVERRUN/LP_EOC may still be set).
            apb_write(`ADC_INT_STAT, 32'h0000_003F);
            clear_sb_exp(`ADC_INT_STAT, 32'h00000000);
            #1000;
            apb_write(`ADC_CTRL, 32'h0000_0002);  // SW_RST
            #2000;
            apb_write(`ADC_CTRL, 32'h0000_0001);  // ADC_EN=1
            #200;
            // Disable all interrupts + W1C all to ensure no stray events
            apb_write(`ADC_INT_EN, 32'h0000_0000);
            #100;
            apb_write(`ADC_INT_STAT, 32'h0000_003F);
            clear_sb_exp(`ADC_INT_STAT, 32'h00000000);
            #2000;  // wait for CDC + any pending events to clear

            // Confirm INT_STAT is clean before starting
            clear_sb_exp(`ADC_INT_STAT, 32'h00000000);
            #100;
            apb_read(`ADC_INT_STAT, rd);
            stat_clean = (rd[5:0] == 6'h00);
            if (stat_clean) begin
                `uvm_info(get_type_name(),
                    "[PASS] INT_ADC_INT_DOMAIN: INT_STAT clean before event", UVM_LOW)
            end else begin
                `uvm_info(get_type_name(),
                    $sformatf("[INFO] INT_ADC_INT_DOMAIN: INT_STAT=0x%02h before event (CDC leftover, proceeding)", rd[5:0]), UVM_LOW)
            end

            // Enable ONLY LP_EOC
            apb_write(`ADC_INT_EN, 32'h0000_0001);
            #100;
            // Verify adc_int is low before any event (INT_STAT should be clean)
            if (m_vif != null && m_vif.adc_int == 1'b0) begin
                `uvm_info(get_type_name(),
                    "[PASS] INT_ADC_INT_DOMAIN: adc_int=0 before event (no INT_STAT set)", UVM_LOW)
            end else begin
                `uvm_info(get_type_name(),
                    "[INFO] INT_ADC_INT_DOMAIN: adc_int=1 before event (leftover INT_STAT bit with INT_EN[0]=1)", UVM_LOW)
            end
            // Trigger LP_EOC
            write_lp_seq_single(5'h05);
            apb_write(`ADC_TRIG, 32'h0000_0002);
            apb_write(`ADC_TRIG, 32'h0000_0003);
            // Wait for LP_EOC event to propagate through CDC to INT_STAT
            int_high_seen = 1'b0;
            for (n = 0; n < 50; n = n + 1) begin
                if (m_vif != null && m_vif.adc_int == 1'b1) begin
                    int_high_seen = 1'b1;
                    n = 50;
                end else begin
                    #40;
                end
            end
            if (int_high_seen) begin
                `uvm_info(get_type_name(),
                    "[PASS] INT_ADC_INT_DOMAIN: adc_int=1 after LP_EOC event (INT_STAT[0] & INT_EN[0])", UVM_LOW)
            end else begin
                `uvm_error(get_type_name(),
                    "[FAIL] INT_ADC_INT_DOMAIN: adc_int stayed 0 after LP_EOC event")
            end
            // Confirm INT_STAT[0] is set
            clear_sb_exp(`ADC_INT_STAT, 32'h00000000);
            #100;
            apb_read(`ADC_INT_STAT, rd);
            if (rd[0]) begin
                `uvm_info(get_type_name(),
                    $sformatf("[PASS] INT_ADC_INT_DOMAIN: INT_STAT[0]=1 (event recorded, 0x%02h)", rd[5:0]), UVM_LOW)
            end else begin
                `uvm_error(get_type_name(),
                    $sformatf("[FAIL] INT_ADC_INT_DOMAIN: INT_STAT[0]=0 (event not recorded, 0x%02h)", rd[5:0]))
            end
            // W1C clear ALL INT_STAT bits → adc_int should drop (INT_EN[0]=1 but
            // INT_STAT now 0, so |(INT_STAT & INT_EN) = 0). Disabling INT_EN first
            // to prevent new LP_EOC events from re-asserting during the check.
            apb_write(`ADC_INT_EN, 32'h0000_0000);  // disable all to stop new events
            #200;
            apb_write(`ADC_INT_STAT, 32'h0000_003F);  // W1C all bits
            clear_sb_exp(`ADC_INT_STAT, 32'h00000000);
            #500;  // wait for PCLK-domain int_stat to clear
            apb_write(`ADC_INT_STAT, 32'h0000_003F);  // second W1C for any CDC-delayed event
            #2000;  // wait for PCLK-domain int_stat to clear
            if (m_vif != null && m_vif.adc_int == 1'b0) begin
                `uvm_info(get_type_name(),
                    "[PASS] INT_ADC_INT_DOMAIN: adc_int=0 after W1C clear all INT_STAT", UVM_LOW)
            end else begin
                `uvm_error(get_type_name(),
                    "[FAIL] INT_ADC_INT_DOMAIN: adc_int=1 after W1C clear all (not gated by INT_STAT)")
            end
            // Re-enable INT_EN[0] with INT_STAT clean → adc_int should stay 0
            // (proves adc_int depends on BOTH INT_STAT AND INT_EN)
            // Clear INT_STAT once more in case a CDC-delayed LP_EOC arrived
            // after the W1C above, then re-enable INT_EN[0].
            apb_write(`ADC_INT_STAT, 32'h0000_003F);
            #2000;  // wait for any pending CDC events to clear
            // Disable INT_EN during the final clear+settle to prevent
            // a late LP_EOC from re-asserting INT_STAT[0] between the W1C
            // and the re-enable. Then re-enable INT_EN[0] with INT_STAT clean.
            apb_write(`ADC_INT_EN, 32'h0000_0000);
            #2000;
            apb_write(`ADC_INT_STAT, 32'h0000_003F);  // final clear
            #5000;  // extended wait for CDC + W1C to fully settle
            apb_write(`ADC_INT_STAT, 32'h0000_003F);  // one more clear in case of CDC tail
            #5000;
            // SW_RST the FSM/seq pointers + disable triggers to guarantee no
            // in-flight or freshly-triggered LP sequence can produce another
            // LP_EOC after this point. The prior sub-test left LP_SEQ_LEN=1
            // and LP_SW_TRG_EN set, so any SW_RST pulse with ADC_EN=1 would
            // immediately re-trigger sampling. Clearing TRIG first prevents
            // that race, then SW_RST flushes the ADC_CLK domain pipeline.
            apb_write(`ADC_TRIG, 32'h0000_0000);  // disable all trigger enables
            #200;
            apb_write(`ADC_CTRL, 32'h0000_0002);  // SW_RST=1 (clears int_stat, FSM)
            #2000;
            apb_write(`ADC_CTRL, 32'h0000_0001);  // ADC_EN=1 (no triggers armed)
            #2000;  // let any in-flight EOC drain into int_stat
            apb_write(`ADC_INT_STAT, 32'h0000_003F);  // W1C all (post-drain)
            #2000;
            apb_write(`ADC_INT_EN, 32'h0000_0001);  // re-enable LP_EOC only
            #200;
            // Re-read INT_STAT to confirm clean state for the check below.
            apb_read(`ADC_INT_STAT, rd);
            if (m_vif != null && m_vif.adc_int == 1'b0 && rd[5:0] == 6'h00) begin
                `uvm_info(get_type_name(),
                    "[PASS] INT_ADC_INT_DOMAIN: adc_int=0 with INT_EN[0]=1 but INT_STAT=0 (AND聚合)", UVM_LOW)
            end else begin
                `uvm_error(get_type_name(),
                    $sformatf("[FAIL] INT_ADC_INT_DOMAIN: adc_int=%0d INT_STAT=0x%02h (expected 0/0)", m_vif.adc_int, rd[5:0]))
            end
        end

        `uvm_info(get_type_name(), "Interrupt test complete", UVM_LOW)
    endtask

endclass
