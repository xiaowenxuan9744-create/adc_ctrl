// ============================================================================
// Interface: adc_if
// Description: Virtual interface for ADC controller DUT
//              Simple modport-based interface without clocking blocks
//              Parameterized: ADC_NUM_CH / ADC_DATA_W (default 26 / 14)
// ============================================================================

interface adc_if #(
    parameter int ADC_NUM_CH = 26,
    parameter int ADC_DATA_W = 14
) (input pclk, input adc_clk, input adc_clkn);

    // 派生位宽（N>=4 → W_CH_SEL = $clog2(N) >= 2）
    localparam int W_CH_SEL = $clog2(ADC_NUM_CH);

    // APB signals (PCLK domain)
    logic        presetn;
    logic [15:0] paddr;
    logic        pwrite;
    logic        psel;
    logic        penable;
    logic [31:0] pwdata;
    logic [31:0] prdata;
    logic        pready;
    logic        pslverr;

    // ADC clocks and reset
    logic        prstn;

    // Analog interface (ADC_CLK domain)
    logic        soc;
    logic        muxon;
    logic [W_CH_SEL-1:0] ch_sel;
    logic        eoc;
    logic [ADC_DATA_W-1:0] adc_data;

    // Calibration
    logic        cal_st;
    logic        cal_done;
    logic [5:0]  cal_val;

    // External triggers (async)
    logic [5:0]  mctm_trig;

    // Interrupt and DMA
    logic        adc_int;
    logic        dma_ndreq;
    logic        dma_ack;

    // Analog preempt reset from DUT (active-low pulse during HP preemption)
    logic        preempt_rst_n;

    // Analog model override (UVM controls ADC data and EOC timing)
    // Driven by adc_driver; when ovrd_en=0 analog model runs self-timed.
    logic        ovrd_en;
    logic        ovrd_force_eoc;
    logic [ADC_DATA_W-1:0] ovrd_adc_data;

    // Modports
    modport apb_master (
        output presetn, paddr, pwrite, psel, penable, pwdata,
        input  prdata, pready, pslverr
    );

    modport apb_slave (
        input  presetn, paddr, pwrite, psel, penable, pwdata,
        output prdata, pready, pslverr
    );

    // cal_done/cal_val are driven by the hardware analog model (u_analog),
    // not by the UVM driver, so they are excluded from adc_driver's modport.
    modport adc_driver (
        output eoc, adc_data, dma_ack, mctm_trig,
        output ovrd_en, ovrd_force_eoc, ovrd_adc_data,
        input  soc, muxon, ch_sel, cal_st, adc_int, dma_ndreq, preempt_rst_n
    );

endinterface
