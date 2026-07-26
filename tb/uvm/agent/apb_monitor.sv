// ============================================================================
// Monitor: apb_monitor
// Description: Monitors APB bus transactions
// ============================================================================

class apb_monitor extends uvm_monitor;
    `uvm_component_utils(apb_monitor)

    virtual adc_if                      m_vif;
    uvm_analysis_port #(adc_txn)        ap;

    function new(string name = "apb_monitor", uvm_component parent = null);
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
            @(posedge m_vif.pclk);
            // Detect valid APB cycle: PSEL && PENABLE
            if (m_vif.psel && m_vif.penable) begin
                txn = adc_txn::type_id::create("txn");
                if (m_vif.pwrite) begin
                    txn.txn_type = WRITE;
                    txn.addr     = m_vif.paddr;
                    txn.data     = m_vif.pwdata;
                end else begin
                    txn.txn_type = READ;
                    txn.addr     = m_vif.paddr;
                    txn.data     = m_vif.prdata;
                end
                ap.write(txn);
            end
        end
    endtask
endclass
