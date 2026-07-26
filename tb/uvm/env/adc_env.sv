// ============================================================================
// Environment: adc_env
// Description: Top-level UVM environment for ADC controller
// ============================================================================

class adc_env extends uvm_env;
    `uvm_component_utils(adc_env)

    apb_agent           m_apb_agent;
    adc_agent           m_adc_agent;
    adc_scoreboard      m_sb;

    function new(string name = "adc_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        m_apb_agent = apb_agent::type_id::create("m_apb_agent", this);
        m_adc_agent = adc_agent::type_id::create("m_adc_agent", this);
        m_sb        = adc_scoreboard::type_id::create("m_sb", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        m_apb_agent.m_monitor.ap.connect(m_sb.apb_export);
        m_adc_agent.m_monitor.ap.connect(m_sb.adc_export);
    endfunction
endclass
