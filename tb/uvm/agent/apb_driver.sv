// ============================================================================
// Driver: apb_driver
// Description: Drives APB bus cycles via virtual interface
//              Zero wait-state APB slave protocol
//              NOTE: Reset is handled by tb_top initial block.
//                    This driver only drives write/read cycles.
//   用 NBA（<=）驱动 APB 信号：NBA 在 active→NBA 区生效，数据落到时钟沿之后，
//   接近真实片外 APB master 的驱动时序（沿后稳定）。对比 unit TB 的 apb_write
//   用阻塞赋值在沿处翻转，SDF 反标后易落进 DUT hold 窗口产生伪违例（见
//   doc/post_sim_report_2026-07-22.md §5a）。UVM gate sim 零延迟运行，此处
//   NBA 仅为风格一致，时序由 +tcheck 在 gate-sim-sdf 统一处理。
// ============================================================================

class apb_driver extends uvm_driver #(adc_txn);
    `uvm_component_utils(apb_driver)

    virtual adc_if m_vif;

    function new(string name = "apb_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual adc_if)::get(this, "", "m_vif", m_vif))
            `uvm_fatal("NOVIF", "Virtual interface not found")
    endfunction

    task run_phase(uvm_phase phase);
        // Defaults (presetn/prstn driven by tb_top)
        m_vif.psel    = 1'b0;
        m_vif.penable = 1'b0;
        m_vif.pwrite  = 1'b0;
        m_vif.paddr   = 16'h0000;
        m_vif.pwdata  = 32'h00000000;

        forever begin
            seq_item_port.get_next_item(req);
            drive_txn(req);
            seq_item_port.item_done();
        end
    endtask

    task drive_txn(adc_txn txn);
        case (txn.txn_type)
            RESET: begin
                // tb_top handles power-on reset; this is a fallback
                m_vif.psel    <= 1'b0;
                m_vif.penable <= 1'b0;
                m_vif.pwrite  <= 1'b0;
            end

            WRITE: begin
                @(posedge m_vif.pclk);
                m_vif.psel    <= 1'b1;
                m_vif.penable <= 1'b0;
                m_vif.pwrite  <= 1'b1;
                m_vif.paddr   <= txn.addr;
                m_vif.pwdata  <= txn.data;
                @(posedge m_vif.pclk);
                m_vif.penable <= 1'b1;
                @(posedge m_vif.pclk);
                m_vif.psel    <= 1'b0;
                m_vif.penable <= 1'b0;
            end

            READ: begin
                @(posedge m_vif.pclk);
                m_vif.psel    <= 1'b1;
                m_vif.penable <= 1'b0;
                m_vif.pwrite  <= 1'b0;
                m_vif.paddr   <= txn.addr;
                @(posedge m_vif.pclk);
                m_vif.penable <= 1'b1;
                @(posedge m_vif.pclk);
                txn.data = m_vif.prdata;
                m_vif.psel    <= 1'b0;
                m_vif.penable <= 1'b0;
            end
        endcase
    endtask
endclass
