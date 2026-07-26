// ============================================================================
// Sequence: adc_dma_seq
// Description: DMA request test sequence
//              DMA_001: LP_EOC trigger DMA — dma_ndreq asserted (low) on EOC
//              DMA_002: ACK clear — dma_ndreq de-asserted (high) on dma_ack
//              DMA_005: Global gate — DMA_EN=0 blocks all requests
//              DMA_007: LP_SEQ_DONE trigger (DMA_CTRL bit2)
//              DMA_008: HP_EOC trigger (DMA_CTRL bit3)
//              DMA_009: HP_SEQ_DONE trigger (DMA_CTRL bit4)
//              DMA_010: OVERRUN trigger (DMA_CTRL bit5)
// ============================================================================

class adc_dma_seq extends adc_base_seq;
    `uvm_object_utils(adc_dma_seq)

    function new(string name = "adc_dma_seq");
        super.new(name);
    endfunction

    task body();
        bit [31:0] rd;

        `uvm_info(get_type_name(), "=== DMA Test ===", UVM_LOW)
        #300;

        // SW_RST for clean CDC state
        apb_write(`ADC_CTRL, 32'h0000_0002);
        #2000;
        apb_write(`ADC_CTRL, 32'h0000_0001);
        #200;

        apb_write(`ADC_CTRL, 32'h0000_0001);
        #200;

        // --- DMA_001: LP_EOC trigger ---
        apb_write(`ADC_DMA_CTRL, 32'h0000_0003);  // DMA_EN + DMA_LP_EOC
        write_lp_seq_single(5'h07);
        apb_write(`ADC_LP_SEQ_LEN, 32'h0000_0001);  // 1-entry LP sequence
        apb_write(`ADC_TRIG, 32'h0000_0002);
        apb_write(`ADC_TRIG, 32'h0000_0003);
        #5000;
        if (!m_vif.dma_ndreq) begin  // active-low: 0 = asserted
            `uvm_info(get_type_name(), "[PASS] DMA_001: dma_ndreq asserted on LP_EOC", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), "[FAIL] DMA_001: dma_ndreq not asserted")
        end

        // --- DMA_002: ACK clear ---
        if (!m_vif.dma_ndreq) begin
            m_vif.dma_ack = 1'b1;
            #100;
            m_vif.dma_ack = 1'b0;
            #200;
            if (m_vif.dma_ndreq) begin  // active-low: 1 = de-asserted
                `uvm_info(get_type_name(), "[PASS] DMA_002: dma_ndreq de-asserted on ack", UVM_LOW)
            end else begin
                `uvm_error(get_type_name(), "[FAIL] DMA_002: dma_ndreq still low after ack")
            end
        end

        // --- DMA_005: Global gate ---
        // Clear all DMA state with SW_RST before testing gating
        apb_write(`ADC_CTRL, 32'h0000_0002);  // SW_RST=1
        #2000;
        apb_write(`ADC_CTRL, 32'h0000_0001);  // ADC_EN=1
        #200;
        // DMA_EN=0, event should NOT produce dma_ndreq
        apb_write(`ADC_DMA_CTRL, 32'h0000_0002);  // DMA_EN=0, DMA_LP_EOC=1
        #2000;  // Wait for CDC sync
        apb_read(`ADC_DMA_CTRL, rd);  // Verify DMA_CTRL write took effect
        if (rd[0] != 0) begin
            `uvm_error(get_type_name(), $sformatf("DMA_CTRL[0] still %0d after write 0", rd[0]))
        end
        write_lp_seq_single(5'h07);
        apb_write(`ADC_LP_SEQ_LEN, 32'h0000_0001);  // 1-entry LP sequence
        apb_write(`ADC_TRIG, 32'h0000_0002);
        apb_write(`ADC_TRIG, 32'h0000_0003);
        #5000;
        // DMA_STAT register deleted — just check dma_ndreq inactive (high)
        if (m_vif.dma_ndreq) begin  // inactive (high) = no request
            `uvm_info(get_type_name(), "[PASS] DMA_005: No dma_ndreq when DMA_EN=0", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), $sformatf("[FAIL] DMA_005: dma_ndreq=%0d (expected inactive/high)", m_vif.dma_ndreq))
        end

        // ─── DMA_007~010: 4 independent enable bits ───
        dma_indep_enable_tests();

        `uvm_info(get_type_name(), "DMA test complete", UVM_LOW)
    endtask

    // ────────────────────────────────────────────────────────────────────────
    // DMA_007~010: 4 independent DMA enable bits
    //   DMA_007: LP_SEQ_DONE (bit2) — LP multi-channel sequence complete
    //   DMA_008: HP_EOC (bit3) — HP single sample complete
    //   DMA_009: HP_SEQ_DONE (bit4) — HP sequence complete
    //   DMA_010: OVERRUN (bit5) — overflow event
    // ────────────────────────────────────────────────────────────────────────
    task dma_indep_enable_tests();
        bit [31:0] rd;
        bit got_req;

        // ---- DMA_007: LP_SEQ_DONE (bit2) ----
        `uvm_info(get_type_name(), "=== DMA_007: LP_SEQ_DONE enable ===", UVM_LOW)
        apb_write(`ADC_CTRL, 32'h0000_0002); #2000; apb_write(`ADC_CTRL, 32'h0000_0001); #200;
        // LP 3-channel sequence, DMA_EN + DMA_LP_SEQ (bit2)
        apb_write(`ADC_DMA_CTRL, 32'h0000_0005);  // EN(bit0) | LP_SEQ(bit2)
        apb_write(`ADC_LP_SEQ0, 32'h00030201);    // CH1,CH2,CH3
        apb_write(`ADC_LP_SEQ1, 32'h00000000);
        apb_write(`ADC_LP_SEQ2, 32'h00000000);
        apb_write(`ADC_LP_SEQ3, 32'h00000000);
        apb_write(`ADC_LP_SEQ4, 32'h00000000);
        apb_write(`ADC_LP_SEQ5, 32'h00000000);
        apb_write(`ADC_LP_SEQ6, 32'h00000000);
        apb_write(`ADC_LP_SEQ7, 32'h00000000);
        apb_write(`ADC_LP_SEQ_LEN, 32'h0000_0003);
        apb_write(`ADC_TRIG, 32'h0000_0002);
        apb_write(`ADC_TRIG, 32'h0000_0003);
        #15000;  // wait for 3-sample sequence to complete → lp_seq_done_pulse
        got_req = !m_vif.dma_ndreq;
        if (got_req) begin
            `uvm_info(get_type_name(), "[PASS] DMA_007: dma_ndreq on LP_SEQ_DONE", UVM_LOW)
            m_vif.dma_ack = 1'b1; #100; m_vif.dma_ack = 1'b0; #300;  // clear
        end else begin
            `uvm_error(get_type_name(), "[FAIL] DMA_007: no dma_ndreq on LP_SEQ_DONE")
        end

        // ---- DMA_008: HP_EOC (bit3) ----
        `uvm_info(get_type_name(), "=== DMA_008: HP_EOC enable ===", UVM_LOW)
        apb_write(`ADC_CTRL, 32'h0000_0002); #2000; apb_write(`ADC_CTRL, 32'h0000_0001); #200;
        apb_write(`ADC_DMA_CTRL, 32'h0000_0009);  // EN(bit0) | HP_EOC(bit3)
        apb_write(`ADC_HP_SEQ, 32'h00000005);     // HP CH5
        apb_write(`ADC_HP_SEQ_LEN, 32'h0000_0001);
        apb_write(`ADC_TRIG, 32'h0000_0200);      // HP_SW_TRG_EN
        #100;  // let EN settle
        apb_write(`ADC_TRIG, 32'h0000_0300);      // HP_SW_TRIG + EN
        #15000;  // wait for HP single sample → hp_eoc_pulse
        got_req = !m_vif.dma_ndreq;
        if (got_req) begin
            `uvm_info(get_type_name(), "[PASS] DMA_008: dma_ndreq on HP_EOC", UVM_LOW)
            m_vif.dma_ack = 1'b1; #100; m_vif.dma_ack = 1'b0; #300;
        end else begin
            `uvm_error(get_type_name(), "[FAIL] DMA_008: no dma_ndreq on HP_EOC")
        end

        // ---- DMA_009: HP_SEQ_DONE (bit4) ----
        `uvm_info(get_type_name(), "=== DMA_009: HP_SEQ_DONE enable ===", UVM_LOW)
        apb_write(`ADC_CTRL, 32'h0000_0002); #2000; apb_write(`ADC_CTRL, 32'h0000_0001); #200;
        apb_write(`ADC_DMA_CTRL, 32'h0000_0011);  // EN(bit0) | HP_SEQ(bit4)
        apb_write(`ADC_HP_SEQ, 32'h00030201);     // HP CH1,CH2,CH3
        apb_write(`ADC_HP_SEQ_LEN, 32'h0000_0003);
        apb_write(`ADC_TRIG, 32'h0000_0200);
        apb_write(`ADC_TRIG, 32'h0000_0300);
        #15000;  // wait for 3 HP samples → hp_seq_done_pulse
        got_req = !m_vif.dma_ndreq;
        if (got_req) begin
            `uvm_info(get_type_name(), "[PASS] DMA_009: dma_ndreq on HP_SEQ_DONE", UVM_LOW)
            m_vif.dma_ack = 1'b1; #100; m_vif.dma_ack = 1'b0; #300;
        end else begin
            `uvm_error(get_type_name(), "[FAIL] DMA_009: no dma_ndreq on HP_SEQ_DONE")
        end

        // ---- DMA_010: OVERRUN (bit5) — removed; OVERRUN no longer triggers DMA ----
        `uvm_info(get_type_name(), "=== DMA_010: OVERRUN enable (SKIPPED — OVERRUN DMA trigger removed) ===", UVM_LOW)
        // OVERRUN is detected in PCLK in regfile and not forwarded to dma_req.
        // The DMA_CTRL[5] bit remains for SW backward-compat but has no effect.
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
