// ============================================================================
// Test: adc_base_test
// Description: Base UVM test for ADC controller
// ============================================================================

class adc_base_test extends uvm_test;
    `uvm_component_utils(adc_base_test)

    adc_env      m_env;
    virtual adc_if m_vif;

    function new(string name = "adc_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        m_env = adc_env::type_id::create("m_env", this);

        if (!uvm_config_db#(virtual adc_if)::get(this, "", "m_vif", m_vif)) begin
            `uvm_fatal("NOVIF", "Virtual interface not set")
        end
    endfunction

    function void end_of_elaboration_phase(uvm_phase phase);
        uvm_top.set_report_verbosity_level(UVM_MEDIUM);
    endfunction
endclass
