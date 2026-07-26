//*********************** Module Header ***************************************
// Module        : adc_int_ctrl
// Description   : Interrupt controller
//                 Forwards raw event pulses (except OVERRUN) to regfile for
//                 PCLK-domain INT_STAT recording and adc_int generation.
//                 OVERRUN is generated inside regfile in the PCLK domain
//                 (detected when the synced LP/HP EOC edge arrives and the
//                 target slot's VALID is still 1), so int_ctrl does NOT
//                 forward an overflow event.
// Clock         : adc_clk
// Reset         : rst_adc_n (asynchronous, active low)
// Parameters:
//   P_SHELL_MODE — 1 = shell mode, all outputs tied to safe values
//******************************************************************************

module adc_int_ctrl #(
    parameter P_SHELL_MODE = 0
) (
    input  wire        adc_clk,
    input  wire        rst_adc_n,

    // Event pulses from adc_seq_fsm
    input  wire        lp_eoc_pulse,
    input  wire        lp_seq_done_pulse,
    input  wire        hp_eoc_pulse,
    input  wire        hp_seq_done_pulse,
    input  wire        hp_preempt_pulse,
    // overflow_event removed — now generated in PCLK in regfile

    // Interrupt events output (to regfile for CDC to PCLK domain)
    //   [0] LP_EOC, [1] LP_SEQ_DONE, [2] HP_EOC, [3] HP_SEQ_DONE,
    //   [4] HP_PREEMPT.  [5] is unused (regfile drives it to 0 and generates
    //   OVERRUN in PCLK).
    output wire [5:0]  int_events
);

    generate
        if (P_SHELL_MODE) begin : gen_shell

            assign int_events = 6'h00;

        end else begin : gen_active

            // Raw events to regfile for INT_STAT: record ALL events (ungated),
            // so INT_STAT captures every event regardless of INT_EN state.
            // Synchronized to PCLK domain via adc_regfile CDC, then edge-detected
            // to set int_stat bits (write-1-to-clear in APB domain).
            // adc_int is generated in PCLK domain as |(int_stat & int_en).
            // OVERRUN (bit5) is generated in PCLK in regfile — tie 0 here.
            assign int_events[0] = lp_eoc_pulse;
            assign int_events[1] = lp_seq_done_pulse;
            assign int_events[2] = hp_eoc_pulse;
            assign int_events[3] = hp_seq_done_pulse;
            assign int_events[4] = hp_preempt_pulse;
            assign int_events[5] = 1'b0;

        end
    endgenerate

endmodule
