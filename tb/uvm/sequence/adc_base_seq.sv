// ============================================================================
// Sequence: adc_base_seq
// Description: Base sequence with common APB operations and vif access
// ============================================================================

class adc_base_seq extends uvm_sequence #(adc_txn);
    `uvm_object_utils(adc_base_seq)

    virtual adc_if m_vif;

    function new(string name = "adc_base_seq");
        super.new(name);
    endfunction

    virtual task pre_body();
        if (m_vif == null) begin
            uvm_config_db#(virtual adc_if)::get(m_sequencer, "", "m_vif", m_vif);
        end
    endtask

    task apb_write(bit [15:0] addr, bit [31:0] data);
        adc_txn txn;
        txn = adc_txn::type_id::create("txn");
        start_item(txn);
        txn.txn_type = WRITE;
        txn.addr     = addr;
        txn.data     = data;
        finish_item(txn);
    endtask

    task apb_read(bit [15:0] addr, output bit [31:0] data);
        adc_txn txn;
        txn = adc_txn::type_id::create("txn");
        start_item(txn);
        txn.txn_type = READ;
        txn.addr     = addr;
        finish_item(txn);
        data = txn.data;
    endtask

    task hw_reset();
        if (m_vif != null) begin
            m_vif.presetn = 1'b0;
            m_vif.prstn   = 1'b0;
            #500;
            m_vif.presetn = 1'b1;
            m_vif.prstn   = 1'b1;
            #500;
        end
    endtask

    task wait_ns(int ns);
        #(ns);
    endtask

    //==========================================================================
    // ch_sel expectation helpers
    // Uses uvm_root hierarchy lookup to find the scoreboard and set/clear
    // expected ch_sel sequences. Every SOC event will be checked.
    //==========================================================================
    task set_ch_sel_expect(bit [4:0] seq[$]);
        adc_scoreboard sb;
        uvm_component comp;
        comp = uvm_root::get().find("uvm_test_top.m_env.m_sb");
        if (comp != null && $cast(sb, comp)) begin
            sb.set_ch_sel_expect(seq);
        end else begin
            `uvm_warning(get_type_name(), "ch_sel: cannot find scoreboard")
        end
    endtask

    task clear_ch_sel_expect();
        adc_scoreboard sb;
        uvm_component comp;
        comp = uvm_root::get().find("uvm_test_top.m_env.m_sb");
        if (comp != null && $cast(sb, comp)) begin
            sb.clear_ch_sel_expect();
        end
    endtask

    //==========================================================================
    // Analog model override helpers
    // When ovrd_en=0 (default): model runs self-timed.
    // When ovrd_en=1: sequence controls EOC timing and ADC data.
    //==========================================================================
    task ovrd_enable(bit [13:0] adc_data = 14'h0000);
        `uvm_info(get_type_name(), $sformatf(
            "Analog model override enabled (adc_data=0x%04h)", adc_data), UVM_MEDIUM)
        m_vif.ovrd_adc_data <= adc_data;
        m_vif.ovrd_en       <= 1'b1;
    endtask

    task ovrd_disable();
        `uvm_info(get_type_name(), "Analog model override disabled", UVM_MEDIUM)
        m_vif.ovrd_en        <= 1'b0;
        m_vif.ovrd_force_eoc <= 1'b0;
    endtask

    // Force EOC at next negedge adc_clk (one pulse)
    task ovrd_force_eoc();
        @(posedge m_vif.adc_clk);
        m_vif.ovrd_force_eoc <= 1'b1;
        @(negedge m_vif.adc_clk);
        m_vif.ovrd_force_eoc <= 1'b0;
    endtask

    // Helper: write LP_SEQ with single channel and set LP_SEQ_LEN=1.
    //   Puts ch in ENT0 (LP_SEQ0[7:0]) and zeros all other entries, then sets
    //   LP_SEQ_LEN=1 so exactly one sample is taken (LP_DATA[0]).
    task write_lp_seq_single(input bit [4:0] ch);
        apb_write(`ADC_LP_SEQ0, {24'h000000, ch[4:0]});
        apb_write(`ADC_LP_SEQ1, 32'h00000000);
        apb_write(`ADC_LP_SEQ2, 32'h00000000);
        apb_write(`ADC_LP_SEQ3, 32'h00000000);
        apb_write(`ADC_LP_SEQ4, 32'h00000000);
        apb_write(`ADC_LP_SEQ5, 32'h00000000);
        apb_write(`ADC_LP_SEQ6, 32'h00000000);
        apb_write(`ADC_LP_SEQ7, 32'h00000000);
        apb_write(`ADC_LP_SEQ_LEN, 32'h0000_0001);
    endtask
endclass
