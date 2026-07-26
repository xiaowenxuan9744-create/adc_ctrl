// ============================================================================
// Monitor: adc_monitor
// Description: Monitors ADC sampling events (SOC, EOC)
// ============================================================================

class adc_monitor extends uvm_monitor;
    `uvm_component_utils(adc_monitor)

    virtual adc_if                      m_vif;
    uvm_analysis_port #(adc_txn)        ap;

    function new(string name = "adc_monitor", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (!uvm_config_db#(virtual adc_if)::get(this, "", "m_vif", m_vif))
            `uvm_fatal("NOVIF", "Virtual interface not found")
    endfunction

    task run_phase(uvm_phase phase);
        adc_txn txn;
        forever begin
            @(posedge m_vif.adc_clk);
            if (m_vif.soc) begin
                // SOC transaction (for logging only)
                txn = adc_txn::type_id::create("txn");
                txn.txn_type = WRITE;
                txn.addr     = 16'h0000;  // SOC marker
                txn.data     = {27'h0, m_vif.ch_sel};
                ap.write(txn);
            end
            if (m_vif.eoc) begin
                txn = adc_txn::type_id::create("txn");
                txn.txn_type = READ;                          // Conversion complete
                // Tag with the channel on the bus AT EOC: in this DUT ch_sel advances
                // on muxon_fall (after SOC), so the SOC-time value is one conversion
                // stale. At EOC ch_sel matches the channel the DUT writes the data to.
                txn.addr     = {11'h000, m_vif.ch_sel};       // addr[4:0] = channel
                txn.adc_sample_data = m_vif.adc_data[13:0];   // Raw ADC data for scoreboard
                txn.data     = {18'h0, m_vif.adc_data};       // Backward compat for logging
                ap.write(txn);
            end
        end
    endtask
endclass
