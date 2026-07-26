// ============================================================================
// Module: adc_analog_model
// Description: Behavioral analog model for ADC
//              - Detects SOC on adc_clk rising edge
//              - Samples voltage while MUXON is high (SPT period controlled
//                by RTL's configurable SPT counter)
//              - Conversion starts on MUXON falling edge
//              - 14-bit SAR conversion
//              - EOC on negedge adc_clk after data ready
//              - Calibration: counts CAL_CYCLES while cal_st high, then asserts
//                cal_done (level) + cal_val; drops them when cal_st deasserts
//              - No CDC, uses both posedge and negedge adc_clk
//              - NOT synthesis-compatible (testbench-only)
// Clock:       adc_clk (only clock input)
// Reset:       prstn (active low)
// ============================================================================

`timescale 1ns / 1ps

module adc_analog_model #(
    parameter CONV_BITS = 14,    // number of SAR conversion cycles (= ADC_DATA_W)
    parameter CAL_CYCLES = 20,   // fixed calibration length (ADC_CLK cycles)
    parameter ADC_NUM_CH = 26,   // 通道数（ch_sel 位宽 = $clog2）
    parameter ADC_DATA_W = 14    // ADC 分辨率（adc_data 宽度，应与 CONV_BITS 一致）
) (
    input  wire        adc_clk,
    input  wire        prstn,
    input  wire        soc,
    input  wire        muxon,
    input  wire [$clog2(ADC_NUM_CH)-1:0]  ch_sel,
    output reg         eoc,
    output reg  [ADC_DATA_W-1:0] adc_data,

    // Analog reset (from DUT preempt_rst_n — HP preemption resets analog per spec)
    input  wire        preempt_rst_n,

    // UVM override interface
    // When ovrd_en=1:
    //   - ovrd_force_eoc pulse forces EOC at negedge (bypass internal conversion)
    //   - ovrd_adc_data replaces random ADC data on next conversion start
    // When ovrd_en=0: normal self-timed behavior (unit TB mode)
    input  wire        ovrd_en,
    input  wire        ovrd_force_eoc,  // pulse, sampled at negedge adc_clk
    input  wire [ADC_DATA_W-1:0] ovrd_adc_data,

    // Calibration interface (mirrors the DUT analog port set)
    //   cal_st    : level from controller (PCLK domain, output directly to analog).
    //               The analog samples it on posedge adc_clk. While high the
    //               analog auto-calibrates.
    //   adc_en    : ADC enable (PCLK domain, output directly). cal_done is forced
    //               to 0 when adc_en=0 (matches the clear condition in spec).
    //   cal_done  : level driven high only after cal_st=1 AND a fixed calibration
    //               time (CAL_CYCLES). Held until cal_st=0 OR adc_en=0 OR reset.
    //   cal_val   : calibration code, stable before cal_done (so the controller
    //               latches the correct value when it sees cal_done=1).
    input  wire        cal_st,
    input  wire        adc_en,
    output reg         cal_done,
    output reg  [5:0]  cal_val
);

    //==========================================================================
    // Parameters
    //==========================================================================
    // (CONV_BITS / CAL_CYCLES 已在 module 参数列表声明)

    //==========================================================================
    // Internal
    //==========================================================================
    reg        sampling_active;
    reg [7:0]  conv_cnt;
    reg        conv_active;
    reg        soc_d1;
    reg        muxon_d1;
    wire       muxon_fall;
    reg        eoc_int;

    //==========================================================================
    // SOC detection + MUXON SPT + conversion (posedge adc_clk)
    //==========================================================================
    // Timing:
    //   1. SOC rising edge → sampling phase starts (voltage tracking)
    //   2. MUXON holds high for configurable SPT cycles (set by RTL)
    //   3. MUXON falling edge → sampling ends, SAR conversion begins
    //   4. CONV_BITS SAR cycles later → EOC on negedge adc_clk
    //==========================================================================
    always @(posedge adc_clk or negedge prstn) begin
        if (!prstn) begin
            sampling_active <= 1'b0;
            conv_cnt        <= 8'h00;
            conv_active     <= 1'b0;
            adc_data        <= {ADC_DATA_W{1'b0}};
            soc_d1          <= 1'b0;
            muxon_d1        <= 1'b0;
            eoc_int         <= 1'b0;
        end else begin
            soc_d1   <= soc;
            muxon_d1 <= muxon;
            eoc_int  <= 1'b0;    // default clear

            // HP preemption: abort ongoing analog conversion per spec ("复位模拟电路").
            // preempt_rst_n is a single-cycle pulse from the DUT that fires during
            // ST_LP_PREEMPT. It aborts any LP conversion in flight, but does NOT
            // clear sampling_active — the HP SOC needs sampling_active to start
            // the HP sampling phase.
            // No EOC is generated here: the controller triggered the preempt and
            // already knows the conversion is aborted. An EOC here would overlap
            // with the HP SOC (both fire within ½ cycle) and could interfere with
            // the HP conversion.
            if (!preempt_rst_n) begin
                conv_cnt    <= 8'h00;
                conv_active <= 1'b0;
            end

            // SOC rising edge → enter sampling phase
            // NOTE: must run regardless of preempt_rst_n so HP SOC is not lost
            if (soc && !soc_d1) begin
                sampling_active <= 1'b1;
            end

            // MUXON falling edge → sampling done, start SAR conversion
            if (sampling_active && muxon_fall) begin
                sampling_active <= 1'b0;
                conv_active     <= 1'b1;
                conv_cnt        <= 8'h00;
                // Sample voltage: UVM-controlled or random
                if (ovrd_en) begin
                    adc_data <= ovrd_adc_data;
                end else begin
                    adc_data <= $random % (1 << CONV_BITS);
                end
            end

            // SAR conversion (counts CONV_BITS cycles from MUXON↓)
            if (conv_active) begin
                if (conv_cnt < CONV_BITS - 1) begin
                    conv_cnt <= conv_cnt + 1;
                end else begin
                    conv_active <= 1'b0;
                    conv_cnt    <= 8'h00;
                    eoc_int     <= 1'b1;    // mark EOC for negedge output
                end
            end
        end
    end

    // MUXON falling edge detect (in adc_clk domain)
    assign muxon_fall = muxon_d1 && ~muxon;

    //==========================================================================
    // EOC on negedge adc_clk (after data is already valid)
    // ovrd_force_eoc bypasses internal conversion timing
    //==========================================================================
    always @(negedge adc_clk or negedge prstn) begin
        if (!prstn) begin
            eoc <= 1'b0;
        end else begin
            eoc <= 1'b0;
            if (ovrd_en && ovrd_force_eoc) begin
                // UVM forces EOC (error injection / timing override)
                eoc <= 1'b1;
            end else if (eoc_int) begin
                // Normal conversion complete
                eoc <= 1'b1;
            end
        end
    end

    //==========================================================================
    // Calibration model (ADC_CLK domain)
    //   cal_st is a PCLK-domain level output directly to the analog; sampled
    //   here on posedge adc_clk. While cal_st=1 the analog counts CAL_CYCLES
    //   ADC_CLK cycles, then raises cal_done (level) + cal_val.
    //   cal_done is set only when cal_st=1 AND the count expired, and is cleared
    //   when cal_st=0 OR adc_en=0 OR reset (per spec). So a fresh cal_st=1
    //   re-arms and re-counts with no reset needed.
    //==========================================================================
    reg [7:0] cal_cnt_r;
    reg       cal_active;

    always @(posedge adc_clk or negedge prstn) begin
        if (!prstn) begin
            cal_cnt_r  <= 8'h00;
            cal_active <= 1'b0;
            cal_done   <= 1'b0;
            cal_val    <= 6'h00;
        end else if (cal_st && adc_en) begin
            if (!cal_active) begin
                // Start of calibration
                cal_active <= 1'b1;
                cal_cnt_r  <= 8'h00;
                cal_done   <= 1'b0;       // re-arm: clear any prior cal_done
                cal_val    <= 6'h00;
            end else if (cal_cnt_r < CAL_CYCLES) begin
                cal_cnt_r <= cal_cnt_r + 8'h01;
                // Pre-load cal_val one cycle before cal_done so it is stable
                // when the controller sees cal_done=1 (after PCLK 2-stage sync).
                if (cal_cnt_r == CAL_CYCLES - 1) begin
                    cal_val <= 6'h2A;     // fixed calibration code
                end
            end else begin
                // Calibration complete — assert and hold cal_done/cal_val while
                // cal_st stays 1 (held until cal_st=0 / adc_en=0 / reset).
                cal_done <= 1'b1;
                cal_val  <= 6'h2A;     // fixed calibration code
            end
        end else begin
            // cal_st=0 or adc_en=0: clear cal_done/cal_val, return to idle so the
            // next cal_st=1 re-arms cleanly.
            cal_active <= 1'b0;
            cal_cnt_r  <= 8'h00;
            cal_done   <= 1'b0;
            cal_val    <= 6'h00;
        end
    end

endmodule
