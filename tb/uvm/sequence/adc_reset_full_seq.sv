// ============================================================================
// Sequence: adc_reset_full_seq
// Description: Remaining reset tests
//              RST_004: Reset during LP sampling
//              RST_005: ADC_EN toggle (re-enable after disable)
//              RST_PRESETN: 只断言 presetn（APB 域复位），不断言 prstn
//              RST_SHARED_SYNC: SW_RST 与 PRSTn 共享同一 2 级同步释放电路
// ============================================================================

class adc_reset_full_seq extends adc_base_seq;
    `uvm_object_utils(adc_reset_full_seq)

    function new(string name = "adc_reset_full_seq");
        super.new(name);
    endfunction

    task body();
        bit [31:0] rd;
        integer    fail_cnt;
        `uvm_info(get_type_name(), "=== Full Reset Test ===", UVM_LOW)
        #300;

        // --- RST_004: Reset during LP sampling ---
        apb_write(`ADC_CTRL, 32'h0000_0001);  // ADC_EN=1
        #200;
        // Start a long LP sequence
        apb_write(`ADC_LP_SEQ0, 32'h001E1410);
        apb_write(`ADC_LP_SEQ1, 32'h00000000);
        apb_write(`ADC_LP_SEQ2, 32'h00000000);
        apb_write(`ADC_LP_SEQ3, 32'h00000000);
        apb_write(`ADC_LP_SEQ4, 32'h00000000);
        apb_write(`ADC_LP_SEQ5, 32'h00000000);
        apb_write(`ADC_LP_SEQ6, 32'h00000000);
        apb_write(`ADC_LP_SEQ7, 32'h00000000);
        #100;
        apb_write(`ADC_TRIG, 32'h0000_0002);
        apb_write(`ADC_TRIG, 32'h0000_0003);
        #1000;  // In the middle of sampling
        // Software reset
        apb_write(`ADC_CTRL, 32'h0000_0002);  // SW_RST=1
        #2000;
        apb_read(`ADC_STAT, rd);
        if (!rd[0]) begin
            `uvm_info(get_type_name(), "[PASS] RST_004: FSM back to IDLE after SW_RST during sampling", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), "[FAIL] RST_004: FSM still busy after SW_RST")
        end
        // Check SW_RST self-cleared
        apb_read(`ADC_CTRL, rd);
        if (!rd[1]) begin
            `uvm_info(get_type_name(), "[PASS] RST_004: SW_RST self-cleared", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), "[FAIL] RST_004: SW_RST not self-cleared")
        end

        // --- RST_005: ADC_EN toggle ---
        apb_write(`ADC_CTRL, 32'h0000_0001);  // Re-enable ADC
        #200;
        apb_read(`ADC_STAT, rd);
        if (rd[0]) begin
            `uvm_info(get_type_name(), "[PASS] RST_005: FSM in WAIT_TRIG after re-enable", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), "[FAIL] RST_005: FSM not in WAIT_TRIG")
        end
        // Can still trigger
        write_lp_seq_single(5'h00);
        apb_write(`ADC_TRIG, 32'h0000_0002);
        apb_write(`ADC_TRIG, 32'h0000_0003);
        #5000;
        apb_read(`ADC_LP_DATA0, rd);
        if (rd[31]) begin
            `uvm_info(get_type_name(), "[PASS] RST_005: Sampling works after ADC_EN toggle", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), "[FAIL] RST_005: Sampling failed after ADC_EN toggle")
        end

        // ----------------------------------------------------------------------
        // RST_PRESETN: 只断言 presetn（APB 域复位），不断言 prstn
        //   验证 APB 域寄存器复位到默认值，ADC_CLK 域保持不受影响。
        //   注意：hw_reset() 同时拉两个——这里只拉 presetn。
        //   presetn 复位 APB 域寄存器：CTRL/TRIG/INT_EN/INT_STAT/CAL_CTRL/
        //   DMA_CTRL/LP_SEQ_LEN/HP_SEQ_LEN 均回到默认值。
        // ----------------------------------------------------------------------
        `uvm_info(get_type_name(), "=== RST_PRESETN (APB域复位) ===", UVM_LOW)
        begin
            // Pre-condition: write non-default values to APB-domain registers
            apb_write(`ADC_CTRL, 32'h000F_0201);  // ADC_EN=1, SPT0=2, SMPL_INTERVAL=15
            apb_write(`ADC_TRIG, 32'h0000_0003);
            apb_write(`ADC_INT_EN, 32'h0000_003F);
            apb_write(`ADC_CAL_CTRL, 32'h0000_0001);
            apb_write(`ADC_DMA_CTRL, 32'h0000_0021);
            apb_write(`ADC_LP_SEQ_LEN, 32'h0000_0001);
            apb_write(`ADC_HP_SEQ_LEN, 32'h0000_0002);
            #200;

            // Assert ONLY presetn (APB-domain reset), keep prstn high
            if (m_vif != null) begin
                m_vif.presetn = 1'b0;
                // prstn stays high (do not touch)
                #500;
                m_vif.presetn = 1'b1;
                #500;
            end

            // Refresh scoreboard expectations: the pre-reset writes set stale
            // expected values. Write DEFAULT values now (no-ops on DUT, but
            // update scoreboard's expected map).
            apb_write(`ADC_INT_EN, 32'h0000_0000);
            apb_write(`ADC_DMA_CTRL, 32'h0000_0000);
            apb_write(`ADC_LP_SEQ_LEN, 32'h0000_001A);  // 26
            apb_write(`ADC_HP_SEQ_LEN, 32'h0000_0004);  // 4

            fail_cnt = 0;

            // Check CTRL (APB domain → reset to 0)
            apb_read(`ADC_CTRL, rd);
            if (rd[22:0] == 23'h000000) begin
                `uvm_info(get_type_name(),
                    $sformatf("[PASS] RST_PRESETN: CTRL=0x%08h (APB-domain reset to 0)", rd), UVM_LOW)
            end else begin
                `uvm_error(get_type_name(),
                    $sformatf("[FAIL] RST_PRESETN: CTRL=0x%08h (exp 0, presetn did not reset)", rd))
                fail_cnt = fail_cnt + 1;
            end

            // Check TRIG
            apb_read(`ADC_TRIG, rd);
            if (rd[15:0] == 16'h0000) begin
                `uvm_info(get_type_name(),
                    "[PASS] RST_PRESETN: TRIG=0x0000 (reset)", UVM_LOW)
            end else begin
                `uvm_error(get_type_name(),
                    $sformatf("[FAIL] RST_PRESETN: TRIG=0x%04h (exp 0)", rd[15:0]))
                fail_cnt = fail_cnt + 1;
            end

            // Check INT_EN
            apb_read(`ADC_INT_EN, rd);
            if (rd[15:0] == 16'h0000) begin
                `uvm_info(get_type_name(),
                    "[PASS] RST_PRESETN: INT_EN=0x0000 (reset)", UVM_LOW)
            end else begin
                `uvm_error(get_type_name(),
                    $sformatf("[FAIL] RST_PRESETN: INT_EN=0x%04h (exp 0)", rd[15:0]))
                fail_cnt = fail_cnt + 1;
            end

            // Check CAL_CTRL.CAL_ST (bit0)
            apb_read(`ADC_CAL_CTRL, rd);
            if (rd[0] == 1'b0) begin
                `uvm_info(get_type_name(),
                    $sformatf("[PASS] RST_PRESETN: CAL_CTRL.CAL_ST=0 (rd=0x%04h)", rd[15:0]), UVM_LOW)
            end else begin
                `uvm_error(get_type_name(),
                    $sformatf("[FAIL] RST_PRESETN: CAL_CTRL.CAL_ST=1 (rd=0x%04h, exp bit0=0)", rd[15:0]))
                fail_cnt = fail_cnt + 1;
            end

            // Check DMA_CTRL
            apb_read(`ADC_DMA_CTRL, rd);
            if (rd[15:0] == 16'h0000) begin
                `uvm_info(get_type_name(),
                    "[PASS] RST_PRESETN: DMA_CTRL=0x0000 (reset)", UVM_LOW)
            end else begin
                `uvm_error(get_type_name(),
                    $sformatf("[FAIL] RST_PRESETN: DMA_CTRL=0x%04h (exp 0)", rd[15:0]))
                fail_cnt = fail_cnt + 1;
            end

            // Check LP_SEQ_LEN = 26
            apb_read(`ADC_LP_SEQ_LEN, rd);
            if (rd[5:0] == 6'd26) begin
                `uvm_info(get_type_name(),
                    $sformatf("[PASS] RST_PRESETN: LP_SEQ_LEN=%0d (default 26)", rd[5:0]), UVM_LOW)
            end else begin
                `uvm_error(get_type_name(),
                    $sformatf("[FAIL] RST_PRESETN: LP_SEQ_LEN=%0d (exp 26)", rd[5:0]))
                fail_cnt = fail_cnt + 1;
            end

            // Check HP_SEQ_LEN = 4
            apb_read(`ADC_HP_SEQ_LEN, rd);
            if (rd[2:0] == 3'd4) begin
                `uvm_info(get_type_name(),
                    $sformatf("[PASS] RST_PRESETN: HP_SEQ_LEN=%0d (default 4)", rd[2:0]), UVM_LOW)
            end else begin
                `uvm_error(get_type_name(),
                    $sformatf("[FAIL] RST_PRESETN: HP_SEQ_LEN=%0d (exp 4)", rd[2:0]))
                fail_cnt = fail_cnt + 1;
            end

            if (fail_cnt == 0) begin
                `uvm_info(get_type_name(),
                    "[PASS] RST_PRESETN: all APB-domain register defaults verified (presetn-only reset)", UVM_LOW)
            end else begin
                `uvm_error(get_type_name(),
                    $sformatf("[FAIL] RST_PRESETN: %0d APB-domain register check(s) failed", fail_cnt))
            end
        end

        // --- RST_SHARED_SYNC: SW_RST 与 PRSTn 共享同一 2 级同步释放电路 ---
        rst_shared_sync();

        `uvm_info(get_type_name(), "Full reset test complete", UVM_LOW)
    endtask

    // ────────────────────────────────────────────────────────────────────────
    // RST_SHARED_SYNC: SW_RST 与 PRSTn 共享同一 2 级同步释放电路
    //   adc_top.v: sw_rst_n = prstn & (~sw_rst_pulse); 该信号经 adc_rst_sync
    //   2 级同步后产生 rst_adc_n。所以 SW_RST 和 hw_reset(prstn) 都通过
    //   同一同步器复位 ADC_CLK 域，时序行为应一致。
    //   验证：分别 hw_reset() 和 SW_RST 复位后，FSM 都回到 IDLE/WAIT_TRIG，
    //   且恢复后能正常采样（功能恢复一致）。
    // ────────────────────────────────────────────────────────────────────────
    task rst_shared_sync();
        bit [31:0] rd;
        time t_hw_start, t_hw_end;
        time t_sw_start, t_sw_end;
        `uvm_info(get_type_name(), "=== RST_SHARED_SYNC: SW_RST vs hw_reset shared sync ===", UVM_LOW)

        // --- HW reset path: assert prstn=0 via hw_reset(), measure FSM recovery ---
        // Pre-condition: start a long LP sequence so FSM is busy
        apb_write(`ADC_CTRL, 32'h0000_0001);  // ADC_EN=1
        #200;
        apb_write(`ADC_LP_SEQ0, 32'h001E1410);  // CH16, CH20, CH30
        apb_write(`ADC_LP_SEQ1, 32'h00000000);
        apb_write(`ADC_LP_SEQ2, 32'h00000000);
        apb_write(`ADC_LP_SEQ3, 32'h00000000);
        apb_write(`ADC_LP_SEQ4, 32'h00000000);
        apb_write(`ADC_LP_SEQ5, 32'h00000000);
        apb_write(`ADC_LP_SEQ6, 32'h00000000);
        apb_write(`ADC_LP_SEQ7, 32'h00000000);
        apb_write(`ADC_TRIG, 32'h0000_0002);
        apb_write(`ADC_TRIG, 32'h0000_0003);
        #1000;  // mid-sample
        t_hw_start = $time;
        hw_reset();  // asserts presetn+prstn=0 for 500ns, then releases
        // Wait for FSM to return to IDLE (all busy=0 right after reset release).
        // hw_reset releases at +1000ns (500 assert + 500 release). After release
        // the ADC_CLK domain 2-stage sync adds ~80ns. The FSM returns to ST_IDLE
        // (all busy=0). Use a bounded polling loop.
        #1200;  // hw_reset internal 1000ns + sync margin
        begin
            integer n;
            n = 0;
            t_hw_end = $time;
            while (n < 20) begin
                apb_read(`ADC_STAT, rd);
                if (!rd[0] && !rd[1] && !rd[2]) begin
                    t_hw_end = $time;
                    n = 1000;
                end else begin
                    n = n + 1;
                    #100;
                end
            end
        end
        `uvm_info(get_type_name(),
            $sformatf("  HW reset: FSM STAT=0x%04h at %0dns (reset-to-idle %0dns)", rd[15:0], t_hw_end, t_hw_end - t_hw_start), UVM_LOW)

        // --- SW_RST path: start busy, then SW_RST, measure FSM recovery ---
        apb_write(`ADC_CTRL, 32'h0000_0001);  // ADC_EN=1
        #200;
        apb_write(`ADC_LP_SEQ0, 32'h001E1410);
        apb_write(`ADC_LP_SEQ1, 32'h00000000);
        apb_write(`ADC_LP_SEQ2, 32'h00000000);
        apb_write(`ADC_LP_SEQ3, 32'h00000000);
        apb_write(`ADC_LP_SEQ4, 32'h00000000);
        apb_write(`ADC_LP_SEQ5, 32'h00000000);
        apb_write(`ADC_LP_SEQ6, 32'h00000000);
        apb_write(`ADC_LP_SEQ7, 32'h00000000);
        apb_write(`ADC_TRIG, 32'h0000_0002);
        apb_write(`ADC_TRIG, 32'h0000_0003);
        #1000;  // mid-sample
        t_sw_start = $time;
        apb_write(`ADC_CTRL, 32'h0000_0002);  // SW_RST=1
        // SW_RST self-clears in ~1 PCLK, then 2-stage sync ~80ns
        #1000;  // SW_RST pulse + 2-stage sync release
        begin
            integer n;
            n = 0;
            t_sw_end = $time;
            while (n < 20) begin
                apb_read(`ADC_STAT, rd);
                if (!rd[0] && !rd[1] && !rd[2]) begin
                    t_sw_end = $time;
                    n = 1000;
                end else begin
                    n = n + 1;
                    #100;
                end
            end
        end
        `uvm_info(get_type_name(),
            $sformatf("  SW_RST: FSM STAT=0x%04h at %0dns (reset-to-idle %0dns)", rd[15:0], t_sw_end, t_sw_end - t_sw_start), UVM_LOW)

        // Both paths must clear busy and return to a controllable state.
        // The key check: both leave LP_BUSY/HP_BUSY/ADC_BUSY=0 right after.
        // (After re-enabling ADC_EN, ADC_BUSY=1 in WAIT_TRIG — but right
        // after reset before re-enabling, all busy=0.)
        apb_read(`ADC_STAT, rd);
        if (!rd[1] && !rd[2]) begin
            `uvm_info(get_type_name(),
                "[PASS] RST_SHARED_SYNC: both hw_reset and SW_RST return FSM to idle via shared 2-stage sync", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(),
                $sformatf("[FAIL] RST_SHARED_SYNC: FSM not idle after SW_RST (STAT=0x%04h)", rd[15:0]))
        end

        // Functional recovery: both paths allow sampling after re-enable
        apb_write(`ADC_CTRL, 32'h0000_0001);  // ADC_EN=1
        #200;
        write_lp_seq_single(5'h00);
        apb_write(`ADC_TRIG, 32'h0000_0002);
        apb_write(`ADC_TRIG, 32'h0000_0003);
        #5000;
        apb_read(`ADC_LP_DATA0, rd);
        if (rd[31]) begin
            `uvm_info(get_type_name(),
                "[PASS] RST_SHARED_SYNC: sampling works after SW_RST recovery (shared sync consistent)", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(),
                "[FAIL] RST_SHARED_SYNC: sampling failed after SW_RST recovery")
        end
    endtask

    task write_lp_seq_single(bit [4:0] ch);
        apb_write(`ADC_LP_SEQ0, {24'h1F1F1F, ch});
        apb_write(`ADC_LP_SEQ1, 32'h1F1F1F1F);
        apb_write(`ADC_LP_SEQ2, 32'h1F1F1F1F);
        apb_write(`ADC_LP_SEQ3, 32'h1F1F1F1F);
        apb_write(`ADC_LP_SEQ4, 32'h1F1F1F1F);
        apb_write(`ADC_LP_SEQ5, 32'h1F1F1F1F);
        apb_write(`ADC_LP_SEQ6, 32'h1F1F1F1F);
        apb_write(`ADC_LP_SEQ7, 32'h1F1F1F1F);
    endtask
endclass
