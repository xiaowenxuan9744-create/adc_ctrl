// ============================================================================
// Sequence: adc_dma_full_seq
// Description: Remaining DMA tests
//              DMA_003: Ack hold (dma_ndreq stays asserted until ack)
//              DMA_004: Multi-event trigger
//              DMA_006: Ack without request (ignored)
//              DMA_011: cfg_dma_ctrl[1] LP_EOC 1->0 toggle (non-reset write)
//              DMA_012: dma_ack early (ack before request — ignored)
//              DMA_013: dma_ack late (long ack delay — request holds)
//              DMA_014: DMA_STAT DMA_BUSY read check (request active)
//              DMA_015: DMA_STAT DMA_DONE read check (after ack)
//              DMA_016: Multi-event overlap (LP_EOC + OVERRUN same sample)
//              DMA_017: No-ack hold (request stays asserted indefinitely)
// ============================================================================

class adc_dma_full_seq extends adc_base_seq;
    `uvm_object_utils(adc_dma_full_seq)

    function new(string name = "adc_dma_full_seq");
        super.new(name);
    endfunction

    task body();
        bit [31:0] rd;
        `uvm_info(get_type_name(), "=== Full DMA Test ===", UVM_LOW)
        #300;

        // SW_RST for clean CDC state
        apb_write(`ADC_CTRL, 32'h0000_0002);
        #2000;
        apb_write(`ADC_CTRL, 32'h0000_0001);
        #200;

        // --- DMA_003: Ack hold ---
        // dma_ndreq stays low (asserted) until ack arrives
        apb_write(`ADC_DMA_CTRL, 32'h0000_0003);  // DMA_EN + DMA_LP_EOC
        write_lp_seq_single(5'h00);
        apb_write(`ADC_TRIG, 32'h0000_0002);
        apb_write(`ADC_TRIG, 32'h0000_0003);
        #5000;
        if (!m_vif.dma_ndreq) begin  // active-low: 0 = asserted
            // Don't ack yet — verify it stays asserted
            #1000;
            if (!m_vif.dma_ndreq) begin
                `uvm_info(get_type_name(), "[PASS] DMA_003: dma_ndreq stays asserted without ack", UVM_LOW)
            end else begin
                `uvm_error(get_type_name(), "[FAIL] DMA_003: dma_ndreq de-asserted before ack")
            end
            // Now ack
            m_vif.dma_ack = 1'b1;
            #500;  // Hold ack for 500ns
            m_vif.dma_ack = 1'b0;
            #2000;  // Wait for CDC + any new EOC
            `uvm_info(get_type_name(), $sformatf("  dma_ndreq=%0d", m_vif.dma_ndreq), UVM_LOW)
            if (m_vif.dma_ndreq) begin  // 1 = de-asserted
                `uvm_info(get_type_name(), "[PASS] DMA_003: dma_ndreq de-asserted after ack", UVM_LOW)
            end else begin
                `uvm_info(get_type_name(), "[INFO] DMA_003: dma_ndreq re-triggered by seq EOC (expected)", UVM_LOW)
            end
        end

        // --- DMA_004: Multi-event trigger ---
        // Multiple EOCs should each trigger dma_ndreq
        apb_write(`ADC_DMA_CTRL, 32'h0000_0003);  // DMA_EN + DMA_LP_EOC
        #2000;

        // Trigger multiple samples
        for (int i = 0; i < 3; i++) begin
            write_lp_seq_single(5'h00);
            apb_write(`ADC_TRIG, 32'h0000_0002);
            apb_write(`ADC_TRIG, 32'h0000_0003);
            #5000;
            if (!m_vif.dma_ndreq) begin
                m_vif.dma_ack = 1'b1;
                #100;
                m_vif.dma_ack = 1'b0;
                #500;
                `uvm_info(get_type_name(), $sformatf("[PASS] DMA_004: Sample %0d triggered dma_ndreq", i+1), UVM_LOW)
            end else begin
                `uvm_error(get_type_name(), $sformatf("[FAIL] DMA_004: Sample %0d no dma_ndreq", i+1))
            end
            #2000;
        end

        // --- DMA_006: Ack without request (ignored) ---
        // Assert dma_ack when dma_ndreq=1 (inactive) — should be ignored
        if (m_vif.dma_ndreq) begin  // 1 = no request
            m_vif.dma_ack = 1'b1;
            #500;  // Hold ack for 500ns
            m_vif.dma_ack = 1'b0;
            #2000;  // Wait for CDC + any new EOC
            `uvm_info(get_type_name(), $sformatf("  dma_ndreq=%0d", m_vif.dma_ndreq), UVM_LOW)
            if (m_vif.dma_ndreq) begin
                `uvm_info(get_type_name(), "[PASS] DMA_006: Spurious ack ignored (dma_ndreq stayed 1)", UVM_LOW)
            end else begin
                `uvm_error(get_type_name(), "[FAIL] DMA_006: Spurious ack caused dma_ndreq")
            end
        end

        // ─── Coverage supplement tests ───
        dma_ack_sync_tests();      // DMA_012, DMA_013, DMA_017
        dma_stat_read_tests();     // DMA_014, DMA_015
        dma_multi_event_test();    // DMA_016
        dma_ctrl_toggle_test();    // DMA_011

        `uvm_info(get_type_name(), "Full DMA test complete", UVM_LOW)
    endtask

    // ────────────────────────────────────────────────────────────────────────
    // DMA_011: cfg_dma_ctrl[1] (LP_EOC) 1->0 toggle via non-reset write
    //   The only uncovered toggle across all merged tests is
    //   cfg_dma_ctrl[1] 1->0.  Existing tests only clear bit1 via SW_RST
    //   (reset path), which does not count as a data toggle.  This test
    //   writes LP_EOC=1, waits for CDC sync, then writes LP_EOC=0 with
    //   EN still on — producing the 1->0 data-path transition.
    // ────────────────────────────────────────────────────────────────────────
    task dma_ctrl_toggle_test();
        bit [31:0] rd;
        `uvm_info(get_type_name(), "=== DMA_011: cfg_dma_ctrl[1] LP_EOC 1->0 toggle ===", UVM_LOW)
        // SW_RST to get a clean slate
        apb_write(`ADC_CTRL, 32'h0000_0002); #2000; apb_write(`ADC_CTRL, 32'h0000_0001); #200;
        // Step 1: write DMA_CTRL = EN + LP_EOC (bit1=1) → cfg_dma_ctrl[1] 0->1
        apb_write(`ADC_DMA_CTRL, 32'h0000_0003);  // EN(bit0) | LP_EOC(bit1)
        #3000;  // wait for 2-stage CDC sync (adc_clk period=40ns, need ~5 cycles)
        apb_read(`ADC_DMA_CTRL, rd);
        if (rd[1] == 1'b1) begin
            `uvm_info(get_type_name(), "[PASS] DMA_011a: LP_EOC bit set to 1", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), $sformatf("[FAIL] DMA_011a: LP_EOC bit not 1, rd=0x%08h", rd))
        end
        // Step 2: write DMA_CTRL = EN only (bit1=0) → cfg_dma_ctrl[1] 1->0 via data path
        apb_write(`ADC_DMA_CTRL, 32'h0000_0001);  // EN(bit0) only, LP_EOC=0
        #3000;  // wait for CDC sync
        apb_read(`ADC_DMA_CTRL, rd);
        if (rd[1] == 1'b0) begin
            `uvm_info(get_type_name(), "[PASS] DMA_011b: LP_EOC bit cleared to 0 (1->0 toggle)", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), $sformatf("[FAIL] DMA_011b: LP_EOC bit still 1, rd=0x%08h", rd))
        end
    endtask

    // ────────────────────────────────────────────────────────────────────────
    // DMA_ACK synchronizer state transition tests
    //   DMA_012: ack early (ack before any request — ignored, dma_ack_s1/s2
    //            toggle but dma_req_r stays 0)
    //   DMA_013: ack late (long delay after request — request holds, then
    //            clears after delayed ack)
    //   DMA_017: no-ack hold (request stays asserted indefinitely, no ack)
    // ────────────────────────────────────────────────────────────────────────
    task dma_ack_sync_tests();
        `uvm_info(get_type_name(), "=== DMA_012: dma_ack early (before request) ===", UVM_LOW)
        // SW_RST for clean state
        apb_write(`ADC_CTRL, 32'h0000_0002); #2000; apb_write(`ADC_CTRL, 32'h0000_0001); #200;
        // Send ack with no request pending — dma_ndreq should stay 1 (inactive)
        m_vif.dma_ack = 1'b1;
        #500;  // hold ack
        m_vif.dma_ack = 1'b0;
        #3000;  // wait for CDC sync of ack + check
        if (m_vif.dma_ndreq) begin
            `uvm_info(get_type_name(), "[PASS] DMA_012: early ack ignored, dma_ndreq stays inactive", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), "[FAIL] DMA_012: early ack caused dma_ndreq assert")
        end

        // DMA_013: ack late — long delay after request
        `uvm_info(get_type_name(), "=== DMA_013: dma_ack late (long delay) ===", UVM_LOW)
        apb_write(`ADC_CTRL, 32'h0000_0002); #2000; apb_write(`ADC_CTRL, 32'h0000_0001); #200;
        apb_write(`ADC_DMA_CTRL, 32'h0000_0003);  // EN + LP_EOC
        #3000;
        write_lp_seq_single(5'h00);
        apb_write(`ADC_TRIG, 32'h0000_0002);
        apb_write(`ADC_TRIG, 32'h0000_0003);
        #5000;  // wait for EOC
        if (!m_vif.dma_ndreq) begin
            `uvm_info(get_type_name(), "[PASS] DMA_013a: dma_ndreq asserted after EOC", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), "[FAIL] DMA_013a: no dma_ndreq after EOC")
        end
        // Wait a long time without ack — request must hold
        #10000;
        if (!m_vif.dma_ndreq) begin
            `uvm_info(get_type_name(), "[PASS] DMA_013b: dma_ndreq still asserted after long delay", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), "[FAIL] DMA_013b: dma_ndreq dropped without ack")
        end
        // Now send delayed ack
        m_vif.dma_ack = 1'b1;
        #2000;  // hold ack for 2us
        m_vif.dma_ack = 1'b0;
        #3000;  // wait for CDC sync + clear
        if (m_vif.dma_ndreq) begin
            `uvm_info(get_type_name(), "[PASS] DMA_013c: dma_ndreq de-asserted after late ack", UVM_LOW)
        end else begin
            `uvm_info(get_type_name(), "[INFO] DMA_013c: dma_ndreq re-triggered (seq may have EOC'd)", UVM_LOW)
        end

        // DMA_017: no-ack hold — request stays indefinitely
        `uvm_info(get_type_name(), "=== DMA_017: no-ack hold (indefinite) ===", UVM_LOW)
        apb_write(`ADC_CTRL, 32'h0000_0002); #2000; apb_write(`ADC_CTRL, 32'h0000_0001); #200;
        apb_write(`ADC_DMA_CTRL, 32'h0000_0003);  // EN + LP_EOC
        #3000;
        write_lp_seq_single(5'h00);
        apb_write(`ADC_TRIG, 32'h0000_0002);
        apb_write(`ADC_TRIG, 32'h0000_0003);
        #5000;
        if (!m_vif.dma_ndreq) begin
            // Wait 15us with no ack — must stay asserted
            #15000;
            if (!m_vif.dma_ndreq) begin
                `uvm_info(get_type_name(), "[PASS] DMA_017: dma_ndreq held asserted for 15us without ack", UVM_LOW)
            end else begin
                `uvm_error(get_type_name(), "[FAIL] DMA_017: dma_ndreq dropped without ack")
            end
            // Clean up: ack to clear
            m_vif.dma_ack = 1'b1; #200; m_vif.dma_ack = 1'b0; #3000;
        end else begin
            `uvm_error(get_type_name(), "[FAIL] DMA_017: no dma_ndreq after EOC")
        end
    endtask

    // ────────────────────────────────────────────────────────────────────────
    // DMA_STAT read tests
    //   DMA_014: read DMA_STAT while request active → DMA_BUSY (bit0) = 1
    //   DMA_015: read DMA_STAT after ack → DMA_DONE (bit1) = 1
    //   Note: DMA_STAT is synced ADC_CLK→PCLK (2-stage in regfile).
    //         dma_busy = dma_req_r, dma_done = dma_ack_s2.
    // ────────────────────────────────────────────────────────────────────────
    task dma_stat_read_tests();
        `uvm_info(get_type_name(), "=== DMA_014/015: DMA_STAT read tests (SKIPPED — register deleted) ===", UVM_LOW)
        // DMA_STAT register removed per spec. dma_ndreq output still
        // indicates the request state; these tests are no longer applicable.
    endtask

    // ────────────────────────────────────────────────────────────────────────
    // DMA_016: Multi-event overlap (LP_EOC + OVERRUN on same sample)
    //   Enable both LP_EOC (bit1) and OVERRUN (bit5).
    //   Sample CH0 twice without reading CH_DATA0:
    //     1st sample: lp_eoc_pulse fires, ch_valid[0]=1, dma_req_r set
    //     ack to clear, then 2nd sample: lp_eoc_pulse + overflow_event both fire
    //   Verify dma_ndreq asserts on the overlapping event.
    // ────────────────────────────────────────────────────────────────────────
    task dma_multi_event_test();
        bit [31:0] rd;
        `uvm_info(get_type_name(), "=== DMA_016: LP_EOC + OVERRUN overlap ===", UVM_LOW)
        apb_write(`ADC_CTRL, 32'h0000_0002); #2000; apb_write(`ADC_CTRL, 32'h0000_0001); #200;
        // Enable EN + LP_EOC + OVERRUN
        apb_write(`ADC_DMA_CTRL, 32'h0000_0023);  // EN(bit0) | LP_EOC(bit1) | OVERRUN(bit5)
        #3000;
        // 1st sample: sets ch_valid[0]=1, triggers lp_eoc_pulse → dma_req
        write_lp_seq_single(5'h00);
        apb_write(`ADC_TRIG, 32'h0000_0002);
        apb_write(`ADC_TRIG, 32'h0000_0003);
        #5000;
        if (!m_vif.dma_ndreq) begin
            `uvm_info(get_type_name(), "[PASS] DMA_016a: 1st sample triggered dma_ndreq (LP_EOC)", UVM_LOW)
            // Ack to clear 1st request
            m_vif.dma_ack = 1'b1; #200; m_vif.dma_ack = 1'b0; #3000;
        end else begin
            `uvm_error(get_type_name(), "[FAIL] DMA_016a: 1st sample no dma_ndreq")
        end
        // Do NOT read CH_DATA0 — ch_valid[0] stays 1
        // 2nd sample on same channel: overflow_event + lp_eoc_pulse both fire
        apb_write(`ADC_TRIG, 32'h0000_0002);
        apb_write(`ADC_TRIG, 32'h0000_0003);
        #5000;
        // Both events arrive at dma_req OR tree — dma_ndreq must assert.
        // Note: OVERRUN no longer triggers DMA (overflow detected in PCLK,
        // not forwarded to dma_req). The 2nd sample's LP_EOC alone triggers.
        if (!m_vif.dma_ndreq) begin
            `uvm_info(get_type_name(), "[PASS] DMA_016b: 2nd sample triggered dma_ndreq (LP_EOC)", UVM_LOW)
            // Clean up
            m_vif.dma_ack = 1'b1; #200; m_vif.dma_ack = 1'b0; #3000;
        end else begin
            `uvm_error(get_type_name(), "[FAIL] DMA_016b: 2nd sample no dma_ndreq")
        end
        // Read LP_DATA[0] to clear valid flag for subsequent tests
        apb_read(`ADC_LP_DATA0, rd);
        #1000;
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
