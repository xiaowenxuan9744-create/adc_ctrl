// ============================================================================
// Agent: adc_agent
// Description: ADC agent — drives analog model, monitors sampling events
// ============================================================================

class adc_agent extends uvm_agent;
    `uvm_component_utils(adc_agent)

    adc_driver      m_driver;
    adc_monitor     m_monitor;
    uvm_sequencer #(adc_txn) m_seqr;

    function new(string name = "adc_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        m_seqr    = uvm_sequencer#(adc_txn)::type_id::create("m_seqr", this);
        m_driver  = adc_driver::type_id::create("m_driver", this);
        m_monitor = adc_monitor::type_id::create("m_monitor", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        m_driver.seq_item_port.connect(m_seqr.seq_item_export);
    endfunction
endclass
