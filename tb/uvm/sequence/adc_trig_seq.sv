// ============================================================================
// Sequence: adc_trig_seq
// Description: Trigger source test sequence
//              TRG_001: MCTM single channel trigger
//              TRG_004: Enable gating — SW_TRG_EN=0 blocks trigger
//              TRG_009: LP/HP simultaneous — HP takes priority
// ============================================================================

class adc_trig_seq extends adc_base_seq;
    `uvm_object_utils(adc_trig_seq)

    function new(string name = "adc_trig_seq");
        super.new(name);
    endfunction

    task body();
        bit [31:0] rd;
        bit hp_sampled;
        bit lp_sampled;

        `uvm_info(get_type_name(), "=== Trigger Test ===", UVM_LOW)
        #300;

        // SW_RST for clean CDC state
        apb_write(`ADC_CTRL, 32'h0000_0002);
        #2000;
        apb_write(`ADC_CTRL, 32'h0000_0001);
        #200;

        // Enable ADC
        apb_write(`ADC_CTRL, 32'h0000_0001);
        #200;

        // --- TRG_001: MCTM trigger ---
        // Configure LP to use MCTM0 as trigger source
        apb_write(`ADC_TRIG, 32'h0000_0004);  // LP_MCTM_EN=1 (bit2), LP_TRG_SEL=0 (mctm0)
        #100;
        write_lp_seq_single(5'h00);

        // Drive MCTM trigger pulse via vif
        m_vif.mctm_trig[0] = 1'b1;
        #100;
        m_vif.mctm_trig[0] = 1'b0;
        #5000;

        apb_read(`ADC_LP_DATA0, rd);  // LP_DATA[0]
        if (rd[31]) begin
            `uvm_info(get_type_name(), "[PASS] TRG_001: MCTM trigger sampled LP slot 0", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), "[FAIL] TRG_001: MCTM trigger did not sample")
        end

        // --- TRG_004: Enable gating ---
        // Wait for previous LP sequence to complete
        #30000;
        // SW_TRG_EN=0, write SW_TRIG — should NOT trigger
        apb_write(`ADC_TRIG, 32'h0000_0000);  // All triggers disabled
        #100;
        apb_write(`ADC_TRIG, 32'h0000_0001);  // LP_SW_TRIG only (no enable)
        #200;
        apb_read(`ADC_STAT, rd);  // STAT
        if (!rd[1]) begin
            `uvm_info(get_type_name(), "[PASS] TRG_004: No trigger when SW_TRG_EN=0", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), "[FAIL] TRG_004: Triggered despite SW_TRG_EN=0")
        end

        // Re-enable and trigger — should work
        apb_write(`ADC_TRIG, 32'h0000_0002);  // LP_SW_TRG_EN only
        apb_write(`ADC_TRIG, 32'h0000_0003);  // LP_SW_TRIG + LP_SW_TRG_EN
        #5000;
        apb_read(`ADC_LP_DATA0, rd);
        if (rd[31]) begin
            `uvm_info(get_type_name(), "[PASS] TRG_004: Trigger works after re-enable", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), "[FAIL] TRG_004: Still no trigger after re-enable")
        end

        // --- TRG_009: LP/HP simultaneous — HP takes priority ---
        // Write both LP and HP SW_TRIG in same cycle — HP should win (sample HP,
        // LP not sampled). Configure distinct LP/HP channels to verify priority.
        apb_write(`ADC_CTRL, 32'h0000_0002); #2000;  // SW_RST
        apb_write(`ADC_CTRL, 32'h0000_0001); #200;   // ADC_EN=1
        write_lp_seq_single(5'h01);   // LP CH1 (sets LP_SEQ_LEN=1)
        apb_write(`ADC_HP_SEQ, 32'h00000008);  // HP CH8
        apb_write(`ADC_HP_SEQ_LEN, 32'h0000_0001);
        apb_read(`ADC_LP_DATA0, rd);  // clear stale
        // LP/HP simultaneous — HP takes priority. LP_SEQ has CH1 in slot 0,
        // HP_SEQ has CH8 in slot 0.
        // First write: enable both SW_TRG_EN. Second write: pulse both SW_TRIG
        // in the same APB write so both edge-detects fire in the same ADC_CLK
        // window — HP wins by FSM priority (hp_trig_pulse checked first).
        apb_write(`ADC_TRIG, 32'h0000_0302);  // LP_SW_TRG_EN + HP_SW_TRG_EN
        #100;  // let EN bits settle through to trig_sync
        apb_write(`ADC_TRIG, 32'h0000_0303);  // + LP_SW_TRIG + HP_SW_TRIG
        #15000;  // wait for HP sample + (rejected) LP trigger to clear
        apb_read(`ADC_HP_DATA0 + 0*4, rd);  // HP_DATA[0] (CH8)
        hp_sampled = rd[31];
        apb_read(`ADC_LP_DATA0 + 0*4, rd);  // LP_DATA[0] (CH1)
        lp_sampled = rd[31];
        if (hp_sampled && !lp_sampled) begin
            `uvm_info(get_type_name(), "[PASS] TRG_009: HP sampled, LP not (HP priority)", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), $sformatf("[FAIL] TRG_009: hp=%0d lp=%0d (expected HP only)", hp_sampled, lp_sampled))
        end

        `uvm_info(get_type_name(), "Trigger test complete", UVM_LOW)
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
