// ============================================================================
// Driver: adc_driver
// Description: Drives analog model configuration signals (dma_ack, mctm_trig)
//              and override control signals for the shared adc_analog_model
//              hardware module instantiated in tb_top.
//
//              EOC, ADC_DATA, cal_done and cal_val are driven by
//              adc_analog_model (self-timed). When error injection is needed,
//              sequence sets ovrd_en via VIF to force EOC timing or ADC data
//              values. Calibration runs automatically: writing CAL_CTRL[0]=1
//              asserts cal_st, the analog model completes after a fixed number
//              of cycles and returns cal_done + cal_val (level) on its own.
// ============================================================================

class adc_driver extends uvm_driver #(adc_txn);
    `uvm_component_utils(adc_driver)

    virtual adc_if m_vif;

    function new(string name = "adc_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual adc_if)::get(this, "", "m_vif", m_vif))
            `uvm_fatal("NOVIF", "Virtual interface not found")
    endfunction

    task run_phase(uvm_phase phase);
        // Defaults for analog outputs driven by this driver.
        // cal_done/cal_val are NOT driven here — they come from u_analog.
        m_vif.dma_ack   = 1'b0;
        m_vif.mctm_trig = 6'h00;

        // Override defaults: model runs self-timed
        m_vif.ovrd_en        = 1'b0;
        m_vif.ovrd_force_eoc = 1'b0;
        m_vif.ovrd_adc_data  = 14'h0000;

        forever begin
            @(posedge m_vif.adc_clk);
            // EOC/ADC_DATA/cal_done/cal_val driven by adc_analog_model (hardware).
            // Sequences control override via m_vif directly (see adc_base_seq).
        end
    endtask
endclass
