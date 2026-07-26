// ============================================================================
// Testbench: tb_top (UVM)
// Description: Top-level UVM testbench for ADC controller
// ============================================================================

`timescale 1ns / 1ps

import uvm_pkg::*;
`include "uvm_macros.svh"

import adc_uvm_pkg::*;

module tb_top;

    //==========================================================================
    // Parameters
    //==========================================================================
    parameter PCLK_PERIOD    = 20;     // 50 MHz
    parameter ADCCLK_PERIOD  = 40;     // 25 MHz
    // 参数化默认配置（与现状一致）：26 通道 / 14bit / SPT1=CH21,22
    parameter ADC_NUM_CH       = 26;
    parameter ADC_DATA_W       = 14;
    parameter ADC_SPT1_CH_MASK = 32'h0060_0000;

    //==========================================================================
    // Clock Generation
    //==========================================================================
    logic pclk    = 0;
    logic adc_clk = 0;
    logic adc_clkn;

    always #(PCLK_PERIOD / 2)   pclk    = ~pclk;
    always #(ADCCLK_PERIOD / 2) adc_clk = ~adc_clk;
    // ADC_CLKn is 180-degree phase-shifted version of ADC_CLK
    // Use separate clock generator, NOT @(adc_clk) to avoid race with posedge sampling
    initial adc_clkn = 1;
    always #(ADCCLK_PERIOD / 2) adc_clkn = ~adc_clkn;

    //==========================================================================
    // Interface
    //==========================================================================
    adc_if #(.ADC_NUM_CH(ADC_NUM_CH), .ADC_DATA_W(ADC_DATA_W)) dut_if (
        .pclk      (pclk),
        .adc_clk   (adc_clk),
        .adc_clkn  (adc_clkn)
    );

    //==========================================================================
    // DUT Instantiation
    //==========================================================================
    adc_top #(.P_SHELL_MODE(0),
              .ADC_NUM_CH(ADC_NUM_CH), .ADC_DATA_W(ADC_DATA_W),
              .ADC_SPT1_CH_MASK(ADC_SPT1_CH_MASK))
    u_dut
    (
        .pclk       (pclk       ),
        .presetn    (dut_if.presetn),
        .paddr      (dut_if.paddr  ),
        .pwrite     (dut_if.pwrite ),
        .psel       (dut_if.psel   ),
        .penable    (dut_if.penable),
        .pwdata     (dut_if.pwdata ),
        .prdata     (dut_if.prdata ),
        .pready     (dut_if.pready ),
        .pslverr    (dut_if.pslverr),

        .adc_clk    (adc_clk    ),
        .adc_clkn   (adc_clkn   ),
        .prstn      (dut_if.prstn),

        .soc        (dut_if.soc    ),
        .muxon      (dut_if.muxon  ),
        .ch_sel     (dut_if.ch_sel ),
        .eoc        (dut_if.eoc    ),
        .adc_data   (dut_if.adc_data),

        .cal_st     (dut_if.cal_st ),
        .cal_done   (dut_if.cal_done),
        .cal_val    (dut_if.cal_val ),

        .mctm_trig  (dut_if.mctm_trig),

        .adc_int    (dut_if.adc_int),
        .dma_ndreq      (dut_if.dma_ndreq),
        .dma_ack        (dut_if.dma_ack),
        .preempt_rst_n  (dut_if.preempt_rst_n)
    );

    //==========================================================================
    // Waveform Dump (FSDB via +fsdb_file=filename command line)
    //==========================================================================
    initial begin
    `ifdef VCS
        string fsdb_file;
        if ($value$plusargs("fsdb_file=%s", fsdb_file))
            $fsdbDumpfile(fsdb_file);
        else
            $fsdbDumpfile("sim/waveform.fsdb");
        $fsdbDumpvars(0, tb_top);
    `else
        $dumpfile("sim/waveform.vcd");
        $dumpvars(0, tb_top);
    `endif
    end

    //==========================================================================
    // Analog Model (shared with unit TB — handles SOC→MUXON→conv→EOC in HW)
    //==========================================================================
    // The hardware model correctly handles overlapping conversions (e.g. HP
    // preemption), unlike the software UVM driver which is single-threaded.
    //==========================================================================
    adc_analog_model #(.CONV_BITS(ADC_DATA_W), .CAL_CYCLES(20),
                        .ADC_NUM_CH(ADC_NUM_CH), .ADC_DATA_W(ADC_DATA_W))
    u_analog (
        .adc_clk        (adc_clk            ),
        .prstn          (dut_if.prstn       ),
        .soc            (dut_if.soc         ),
        .muxon          (dut_if.muxon       ),
        .ch_sel         (dut_if.ch_sel      ),
        .eoc            (dut_if.eoc         ),
        .adc_data       (dut_if.adc_data    ),
        .preempt_rst_n  (dut_if.preempt_rst_n),
        .ovrd_en        (dut_if.ovrd_en     ),
        .ovrd_force_eoc (dut_if.ovrd_force_eoc),
        .ovrd_adc_data  (dut_if.ovrd_adc_data),
        .cal_st         (dut_if.cal_st      ),
        .adc_en         (u_dut.cfg_adc_en   ),  // ADC_EN (PCLK-domain, synced to ADC_CLK)
        .cal_done       (dut_if.cal_done    ),
        .cal_val        (dut_if.cal_val     )
    );

    //==========================================================================
    // Reset
    //==========================================================================
    initial begin
        // Set remaining analog outputs to default (driven by ADC driver in UVM)
        // NOTE: cal_done/cal_val are now driven by u_analog (auto-calibration
        // model), not by the sequence/driver. Keep dma_ack/mctm_trig defaults.
        dut_if.dma_ack   = 1'b0;
        dut_if.mctm_trig = 6'h00;

        // Set virtual interface at time 0 (must be before run_test)
        uvm_config_db#(virtual adc_if)::set(null, "*", "m_vif", dut_if);

        // Run UVM immediately (must be at time 0)
        run_test();
    end

    // External power-on reset: assert for 200ns then release.
    // NOTE: presetn/prstn are NOT driven by UVM APB driver to avoid multi-driver conflicts.
    // The hw_reset in the sequence drives these via the APB driver for intermediate resets.
    initial begin
        dut_if.presetn = 1'b0;
        dut_if.prstn   = 1'b0;
        #200;
        dut_if.presetn = 1'b1;
        dut_if.prstn   = 1'b1;
    end

    //==========================================================================
    // Timeout
    //==========================================================================
    initial begin
        #800000;
        `uvm_fatal("TIMEOUT", "Simulation timed out")
        $finish;
    end

endmodule
