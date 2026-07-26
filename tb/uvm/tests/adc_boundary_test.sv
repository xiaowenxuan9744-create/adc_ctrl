class adc_boundary_test extends adc_base_test;
    `uvm_component_utils(adc_boundary_test)
    adc_boundary_seq m_seq;
    function new(string name = "adc_boundary_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        m_seq = adc_boundary_seq::type_id::create("m_seq");
    endfunction
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        `uvm_info(get_type_name(), "Boundary test started", UVM_LOW)
        m_seq.start(m_env.m_apb_agent.m_seqr);
        `uvm_info(get_type_name(), "Boundary test done", UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass
