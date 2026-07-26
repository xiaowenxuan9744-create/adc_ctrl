// ============================================================================
// Package: adc_uvm_pkg
// Description: UVM package for ADC controller verification
// ============================================================================

package adc_uvm_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // Register map: address + field macros (single source of truth, generated
    // by regmap-gen). Sequence files use `ADC_* instead of hardcoded addresses.
    // NOTE: macros are 32-bit (32'hxx); apb_write/read take bit[15:0] addr and
    // SV truncates implicitly — safe because all defined offsets fit in 16 bits.
    `include "adc_regmap.svh"

    // ---- 参数化配置宏（默认 26 通道 / 14bit / SPT1=CH21,22）----
    // Sequence/scoreboard 用 `ADC_NUM_CH / `ADC_DATA_W 做条件分支与位宽派生。
    // 可在 VCS 编译时 +define+ADC_NUM_CH=8 等覆盖（8 通道 smoke）。
    `ifndef ADC_NUM_CH
    `define ADC_NUM_CH 26
    `endif
    `ifndef ADC_DATA_W
    `define ADC_DATA_W 14
    `endif
    // LP_SEQ_LEN 位宽 = $clog2(ADC_NUM_CH+1)（N>=4 → >=3）；regmap 默认宏 ADC_LP_SEQ_LEN_W=6
    // 按 32 通道上限，此处按实际参数重定义供 sequence sweep mask 用。
    `undef  ADC_LP_SEQ_LEN_W
    `define ADC_LP_SEQ_LEN_W  $clog2((`ADC_NUM_CH)+1)

    // LP_SEQ/HP_SEQ entry ch_sel 位宽 = $clog2(ADC_NUM_CH)；entry 内 rsv 高位读回 0。
    // sweep mask：每个 8bit 占位只低 W_CH_SEL bit 可写/可比对，4 entry 拼 32bit mask。
    `undef  ADC_SEQ_CH_SEL_W
    `define ADC_SEQ_CH_SEL_W  $clog2((`ADC_NUM_CH))
    // 单 entry 8bit 占位的 ch_sel mask = 低 W_CH_SEL bit
    `undef  ADC_SEQ_ENTRY_MASK
    `define ADC_SEQ_ENTRY_MASK  ((1<<`ADC_SEQ_CH_SEL_W)-1)
    // LP_SEQ/HP_SEQ 32bit sweep mask = 4 entry 占位各取低 W_CH_SEL bit
    `undef  ADC_SEQ_REG_MASK
    `define ADC_SEQ_REG_MASK  (`ADC_SEQ_ENTRY_MASK | (`ADC_SEQ_ENTRY_MASK<<8) | (`ADC_SEQ_ENTRY_MASK<<16) | (`ADC_SEQ_ENTRY_MASK<<24))

    // Transaction types
    typedef enum bit [1:0] {
        RESET,
        WRITE,
        READ
    } txn_type_e;

    //==========================================================================
    // Transaction: adc_txn
    //==========================================================================
    class adc_txn extends uvm_sequence_item;
        `uvm_object_utils(adc_txn)

        rand txn_type_e txn_type;
        rand bit [15:0] addr;
        rand bit [31:0] data;
        rand bit [31:0] expected;
        rand bit [5:0]  mctm_trig;
        rand bit [13:0] adc_sample_data;
        rand int        delay_cycles;

        constraint c_addr_range {
            addr[1:0] == 2'b00;  // Word-aligned
        }

        constraint c_delay {
            delay_cycles inside {[0:10]};
        }

        function new(string name = "adc_txn");
            super.new(name);
        endfunction

        function string convert2string();
            return $sformatf("txn_type=%s addr=0x%04h data=0x%08h",
                txn_type.name(), addr, data);
        endfunction
    endclass

    // Include all components (ordered by dependency)
    `include "apb_driver.sv"
    `include "apb_monitor.sv"
    `include "apb_agent.sv"
    `include "adc_driver.sv"
    `include "adc_monitor.sv"
    `include "adc_agent.sv"
    `include "adc_sb.sv"         // Before env — adc_env depends on adc_scoreboard
    `include "adc_env.sv"
    `include "adc_base_seq.sv"
    `include "adc_reg_seq.sv"
    `include "adc_sample_seq.sv"
    `include "adc_sequence_seq.sv"
    `include "adc_int_seq.sv"
    `include "adc_dma_seq.sv"
    `include "adc_calib_seq.sv"
    `include "adc_reset_seq.sv"
    `include "adc_hp_seq.sv"
    `include "adc_trig_seq.sv"
    `include "adc_data_seq.sv"
    `include "adc_boundary_seq.sv"
    `include "adc_cont_seq.sv"
    `include "adc_trig_full_seq.sv"
    `include "adc_int_full_seq.sv"
    `include "adc_dma_full_seq.sv"
    `include "adc_calib_full_seq.sv"
    `include "adc_reset_full_seq.sv"
    `include "adc_reg_full_seq.sv"
    `include "adc_base_test.sv"
    `include "adc_reg_test.sv"
    `include "adc_sample_test.sv"
    `include "adc_sequence_test.sv"
    `include "adc_int_test.sv"
    `include "adc_dma_test.sv"
    `include "adc_calib_test.sv"
    `include "adc_reset_test.sv"
    `include "adc_hp_test.sv"
    `include "adc_trig_test.sv"
    `include "adc_data_test.sv"
    `include "adc_boundary_test.sv"
    `include "adc_cont_test.sv"
    `include "adc_trig_full_test.sv"
    `include "adc_int_full_test.sv"
    `include "adc_dma_full_test.sv"
    `include "adc_calib_full_test.sv"
    `include "adc_reset_full_test.sv"
    `include "adc_reg_full_test.sv"

endpackage
