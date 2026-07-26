// ============================================================================
// Test: adc_reg_full_test
// Description: Full register coverage UVM test (coverage hole closure)
//              Runs adc_reg_full_seq which exercises:
//                REG_010: INT_STAT per-bit independent W1C clear
//                REG_011: INT_EN  per-bit independent enable toggle
//                REG_012: DATA_ALIGN left/right toggle
//                REG_013: CH_DATA[26:31] sampled via LP_SEQ_LEN=32
//                REG_014: CAL_ST toggle (cal_st 0->1->0)
//                REG_015: DMA_STAT toggle (dma_busy/dma_done via DMA + ack)
// ============================================================================

class adc_reg_full_test extends adc_base_test;
    `uvm_component_utils(adc_reg_full_test)

    adc_reg_full_seq m_seq;

    function new(string name = "adc_reg_full_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        m_seq = adc_reg_full_seq::type_id::create("m_seq");
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        `uvm_info(get_type_name(), "Full register test started", UVM_LOW)
        m_seq.start(m_env.m_apb_agent.m_seqr);
        `uvm_info(get_type_name(), "Full register test done", UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass
