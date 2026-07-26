//*********************** Module Header ***************************************
// Module        : adc_seq_fsm
// Description   : ADC core sampling state machine
//                 Controls SOC/MUXON timing, SPT/interval counters,
//                 sequence traversal, and high-priority preemption.
// Clock         : adc_clk (primary), adc_clkn (for SOC pulse)
// Reset         : rst_adc_n (asynchronous, active low)
// Parameters:
//   P_SHELL_MODE — 1 = shell mode, all outputs tied to safe values
//******************************************************************************
module adc_seq_fsm #(
    parameter P_SHELL_MODE = 0,
    parameter ADC_NUM_CH = 26,
    parameter ADC_DATA_W = 14,
    parameter ADC_SPT1_CH_MASK = 32'h0060_0000
`include "adc_params.vh"
) (
    // 派生 localparam 在端口列表中可见（module body 内 `include adc_params.vh
    // 声明为 module 级 localparam；iverilog -g2005 允许端口声明引用 module 级
    // localparam？实测：localparam 必须在端口声明前可见。故用 parameter 派生
    // 放在 #(...) 内紧接主参数后——但 -g2005 不支持 ANSI 列表内 localparam。
    // 解决：端口位宽改用主参数表达式内联，不引用派生 localparam。
    // Clocks and reset
    input  wire        adc_clk,
    input  wire        adc_clkn,
    input  wire        rst_adc_n,

    // Configuration (from regfile, synchronized to ADC_CLK domain)
    input  wire        cfg_adc_en,
    input  wire [6:0]  cfg_smpl_interval,
    input  wire [2:0]  cfg_spt0,
    input  wire [2:0]  cfg_spt1,
    input  wire        cfg_data_align,
    input  wire        cfg_cont_mode,

    // Sequence configuration
    //   W_LP_SEQ_LEN = $clog2(ADC_NUM_CH+1)，端口用表达式内联
    input  wire [$clog2(ADC_NUM_CH+1)-1:0] cfg_lp_seq_len,
    input  wire [2:0]                      cfg_hp_seq_len,
    // LP/HP sequence entries：packed bus，entry i 在 [i*W_CH_SEL +: W_CH_SEL]（ch_sel 粒度）
    input  wire [W_CH_SEL*ADC_NUM_CH-1:0] cfg_lp_seq_flat,
    input  wire [W_CH_SEL*4-1:0]          cfg_hp_seq_flat,

    // Triggers (from trig_sync, ADC_CLK domain)
    input  wire        lp_trig_pulse,
    input  wire        hp_trig_pulse,

    // Analog interface
    input  wire        eoc,
    input  wire [ADC_DATA_W-1:0] adc_data,

    // Analog output
    //   W_CH_SEL = $clog2(ADC_NUM_CH) (N>=4 → >=2)
    output wire        soc,
    output wire        muxon,
    output wire [$clog2(ADC_NUM_CH)-1:0] ch_sel,

    // Status (to regfile)
    output wire        stat_adc_busy,
    output wire        stat_lp_busy,
    output wire        stat_hp_busy,

    // LP_DATA / HP_DATA write (to regfile, ADC_CLK domain)
    //   W_LP_DATA_WEN = ADC_NUM_CH, W_HP_DATA_WEN = 4, W_EOC_IDX = W_CH_SEL,
    //   DATA_FIELD_W = 16
    output wire [ADC_NUM_CH-1:0] lp_data_wr_en,
    output wire [15:0]           lp_data_wr_din,
    output wire [3:0]            hp_data_wr_en,
    output wire [15:0]           hp_data_wr_din,
    output wire [$clog2(ADC_NUM_CH)-1:0] eoc_idx,

    // Events (to int_ctrl and dma_req)
    //   overflow_event removed — now generated in PCLK in regfile.
    output wire        lp_eoc_pulse,
    output wire        lp_seq_done_pulse,
    output wire        hp_eoc_pulse,
    output wire        hp_seq_done_pulse,
    output wire        hp_preempt_pulse,

    // Analog reset (pulsed on HP preempt — spec requires "复位模拟电路")
    output wire        preempt_rst_n
);
    `include "adc_params_check.vh"

    //==========================================================================
    // Shared signals (declared at module level for VCS generate scope)
    //==========================================================================
    reg soc_req_set;
    reg preempt_abort;
    reg preempt_soc_pend;

    //==========================================================================
    // Shell Mode
    //==========================================================================
    generate
        if (P_SHELL_MODE) begin : gen_shell

            assign soc             = 1'b0;
            assign muxon           = 1'b0;
            assign ch_sel          = {W_CH_SEL{1'b0}};
            assign stat_adc_busy   = 1'b0;
            assign stat_lp_busy    = 1'b0;
            assign stat_hp_busy    = 1'b0;
            assign lp_data_wr_en   = {W_LP_DATA_WEN{1'b0}};
            assign lp_data_wr_din  = {DATA_FIELD_W{1'b0}};
            assign hp_data_wr_en   = {W_HP_DATA_WEN{1'b0}};
            assign hp_data_wr_din  = {DATA_FIELD_W{1'b0}};
            assign eoc_idx         = {W_EOC_IDX{1'b0}};
            assign lp_eoc_pulse    = 1'b0;
            assign lp_seq_done_pulse = 1'b0;
            assign hp_eoc_pulse    = 1'b0;
            assign hp_seq_done_pulse = 1'b0;
            assign hp_preempt_pulse = 1'b0;
            assign cfg_cont_mode   = 1'b0;
            assign preempt_rst_n   = 1'b1;

        end else begin : gen_active

            //==========================================================================
            // Parameters: FSM States
            //==========================================================================
            localparam ST_IDLE        = 4'h0;
            localparam ST_WAIT_TRIG   = 4'h1;
            localparam ST_LP_SAMPLE   = 4'h2;
            localparam ST_LP_WAIT_EOC = 4'h3;
            localparam ST_LP_INTERVAL = 4'h4;
            localparam ST_HP_SAMPLE   = 4'h5;
            localparam ST_HP_WAIT_EOC = 4'h6;
            localparam ST_HP_INTERVAL = 4'h7;
            localparam ST_LP_PREEMPT  = 4'h8;

            //==========================================================================
            // Internal Signals
            //==========================================================================

            // FSM state registers
            reg [3:0] fsm_curr_st;
            reg [3:0] fsm_next_st;

            // Sequence pointers
            reg [W_LP_SEQ_PTR-1:0] lp_seq_ptr;     // 0~ADC_NUM_CH-1
            reg [W_HP_SEQ_PTR-1:0] hp_seq_ptr;     // 0~3
            reg [W_LP_SEQ_PTR-1:0] lp_save_ptr;    // Saved LP pointer during preemption

            // Sequence entry extraction（ch_sel 粒度，元素宽 = W_CH_SEL）
            wire [W_CH_SEL-1:0] lp_entry_array [0:ADC_NUM_CH-1];
            wire [W_CH_SEL-1:0] hp_entry_array [0:3];
            wire [W_CH_SEL-1:0] lp_ch_sel;
            wire [W_CH_SEL-1:0] hp_ch_sel;
            reg  [W_CH_SEL-1:0] cur_ch_sel;

            // SPT counter
            reg [7:0] spt_cnt;
            reg [7:0] spt_thresh;
            wire spt_done;

            // Interval counter
            reg [7:0] interval_cnt;
            reg interval_cnt_en;
            wire interval_done;

            // MUXON register (in adc_clkn domain)
            reg muxon_reg;

            // MUXON cross-domain signals (in adc_clk domain)
            reg muxon_clk;
            reg muxon_dly;
            wire muxon_fall;

            // EOC detection
            reg eoc_sync1;
            reg eoc_sync2;
            wire eoc_captured;

            // Data capture
            reg [ADC_DATA_W-1:0] adc_data_d1;       // Pipeline: adc_data sampled every cycle
            reg [ADC_DATA_W-1:0] adc_data_capt;
            reg [DATA_FIELD_W-1:0] data_aligned;

            // Event pulse generation
            reg lp_eoc_pulse_r;
            reg lp_seq_done_pulse_r;
            reg hp_eoc_pulse_r;
            reg hp_seq_done_pulse_r;
            reg hp_preempt_pulse_r;

            // EOC index capture (seq_ptr at the EOC cycle) — forwarded to
            // regfile so PCLK can set the matching LP/HP VALID slot.
            reg [W_EOC_IDX-1:0]  eoc_idx_r;

            // LP/HP data write pulses + data (one-hot over sequence slots)
            reg [W_LP_DATA_WEN-1:0] lp_data_wr_en_r;
            reg [DATA_FIELD_W-1:0]  lp_data_wr_din_r;
            reg [W_HP_DATA_WEN-1:0] hp_data_wr_en_r;
            reg [DATA_FIELD_W-1:0]  hp_data_wr_din_r;

            // Single/continuous mode (from CTRL)
            // cfg_cont_mode=0: single-shot per trigger (stop after sequence)
            // cfg_cont_mode=1: continuous (auto-restart after sequence)

            // Loop index
            integer i;

            //==========================================================================
            // Sequence Entry Decode
            //==========================================================================

            // Extract ADC_NUM_CH W_CH_SEL-bit LP ch_sel from packed bus (entry i @ [i*W_CH_SEL +: W_CH_SEL])
            // regfile 内部已按 ch_sel 粒度存储，此处直切无需拆组。
            genvar gi;
            for (gi = 0; gi < ADC_NUM_CH; gi = gi + 1) begin : gen_lp_entry
                assign lp_entry_array[gi] = cfg_lp_seq_flat[gi*W_CH_SEL +: W_CH_SEL];
            end

            // Extract 4 W_CH_SEL-bit HP ch_sel from packed bus (HP 固定 4 条)
            assign hp_entry_array[0] = cfg_hp_seq_flat[0*W_CH_SEL +: W_CH_SEL];
            assign hp_entry_array[1] = cfg_hp_seq_flat[1*W_CH_SEL +: W_CH_SEL];
            assign hp_entry_array[2] = cfg_hp_seq_flat[2*W_CH_SEL +: W_CH_SEL];
            assign hp_entry_array[3] = cfg_hp_seq_flat[3*W_CH_SEL +: W_CH_SEL];

            // Channel selection = entry（元素已是 W_CH_SEL bit，无需再切片）
            assign lp_ch_sel = lp_entry_array[lp_seq_ptr];
            assign hp_ch_sel = hp_entry_array[hp_seq_ptr];

            //==========================================================================
            // SPT Threshold Selection
            //==========================================================================
            // combo logic
            // SPT1 通道由 ADC_SPT1_CH_MASK 位图决定：bit i=1 → 通道 i 用 SPT1
            // 默认 mask=32'h0060_0000 (CH21/CH22)，与原硬编码一致
            always @(*) begin
                if (ADC_SPT1_CH_MASK[cur_ch_sel]) begin
                    spt_thresh = cfg_spt1;
                end else begin
                    spt_thresh = cfg_spt0;
                end
            end

            //==========================================================================
            // SPT Time Table
            //==========================================================================
            // combo logic
            reg [7:0] spt_cycles;
            always @(*) begin
                case (spt_thresh)
                    3'h0: spt_cycles = 8'd3;
                    3'h1: spt_cycles = 8'd8;
                    3'h2: spt_cycles = 8'd14;
                    3'h3: spt_cycles = 8'd29;
                    3'h4: spt_cycles = 8'd42;
                    3'h5: spt_cycles = 8'd56;
                    3'h6: spt_cycles = 8'd78;
                    3'h7: spt_cycles = 8'd240;
                    default: spt_cycles = 8'd3;
                endcase
            end

            //==========================================================================
            // SPT Counter (posedge adc_clkn domain — same edge as MUXON)
            //==========================================================================
            // Counts from the same posedge adc_clkn where SOC/MUXON fire,
            // so MUXON is high for exactly spt_cycles of ADC_CLK.
            // seq logic
            reg spt_active;
            always @(posedge adc_clkn or negedge rst_adc_n) begin
                if (!rst_adc_n) begin
                    spt_cnt    <= 8'h00;
                    spt_active <= 1'b0;
                end else if (soc_req_set) begin
                    // Start / restart counting — same edge as MUXON rise.
                    // !spt_active is intentionally NOT guarded: when HP preempts LP
                    // from ST_LP_SAMPLE, soc_req_set is driven by preempt_soc_pend
                    // (set in ST_LP_PREEMPT, consumed in ST_HP_SAMPLE) and MUST
                    // restart the SPT counter for HP's sampling phase.
                    // (LP was interrupted mid-SPT; the counter was still busy.)
                    spt_cnt    <= 8'h00;
                    spt_active <= 1'b1;
                end else if (spt_active) begin
                    if (spt_cnt < spt_cycles) begin
                        spt_cnt <= spt_cnt + 1;
                    end else begin
                        // SPT complete
                        spt_cnt    <= 8'h00;
                        spt_active <= 1'b0;
                    end
                end
            end

            assign spt_done = spt_active && (spt_cnt == spt_cycles);

            //==========================================================================
            // Interval Counter
            //==========================================================================
            // seq logic
            always @(posedge adc_clk or negedge rst_adc_n) begin
                if (!rst_adc_n) begin
                    interval_cnt <= 8'h00;
                end else if (interval_cnt_en) begin
                    if (interval_cnt < cfg_smpl_interval) begin
                        interval_cnt <= interval_cnt + 1;
                    end else begin
                        interval_cnt <= 8'h00;
                    end
                end else begin
                    interval_cnt <= 8'h00;
                end
            end

            // interval done when count reaches configured value
            assign interval_done = (interval_cnt[6:0] == cfg_smpl_interval) && interval_cnt_en;

            //==========================================================================
            // MUXON + SOC Generation (on posedge adc_clkn ≡ negedge adc_clk)
            //==========================================================================
            // SOC and MUXON rise together on posedge adc_clkn, so the analog
            // circuit detects SOC on the very next posedge adc_clk — saving 1 cycle
            // versus producing SOC at posedge adc_clk.
            // soc_req_set from the ADC_CLK-domain FSM is stable for >½ cycle
            // (=8.3 ns @ 60 MHz), plenty for synthesis to close timing.

            // SOC pulse (single-cycle at posedge adc_clkn)
            reg soc_pulse_clkn;
            always @(posedge adc_clkn or negedge rst_adc_n) begin
                if (!rst_adc_n) begin
                    soc_pulse_clkn <= 1'b0;
                end else begin
                    soc_pulse_clkn <= 1'b0;  // default: clear
                    if (soc_req_set) begin
                        soc_pulse_clkn <= 1'b1;
                    end
                end
            end

            // SOC output: direct from clkn domain to analog (no CDC — analog
            // detects on next posedge adc_clk, ½ cycle later)
            assign soc = soc_pulse_clkn;

            // (SOC is output directly from clkn domain; no CDC needed)

            // MUXON (posedge adc_clkn domain) — output directly to analog
            always @(posedge adc_clkn or negedge rst_adc_n) begin
                if (!rst_adc_n) begin
                    muxon_reg <= 1'b0;
                end else begin
                    if (soc_req_set) begin
                        muxon_reg <= 1'b1;
                    end else if (spt_done) begin
                        muxon_reg <= 1'b0;
                    end else if (preempt_abort) begin
                        muxon_reg <= 1'b0;
                    end
                end
            end
            assign muxon = muxon_reg;

            // MUXON cross-domain sampling into ADC_CLK domain.
            // adc_clk and adc_clkn are synchronous (180° phase shift from the
            // same source) — a single flop suffices, no 2-stage CDC needed.
            always @(posedge adc_clk or negedge rst_adc_n) begin
                if (!rst_adc_n) begin
                    muxon_clk <= 1'b0;
                end else begin
                    muxon_clk <= muxon_reg;
                end
            end

            // MUXON falling edge detect (in ADC_CLK domain)
            always @(posedge adc_clk or negedge rst_adc_n) begin
                if (!rst_adc_n) begin
                    muxon_dly <= 1'b0;
                end else begin
                    muxon_dly <= muxon_clk;
                end
            end
            assign muxon_fall = muxon_dly & (~muxon_clk);

            //==========================================================================
            // ch_sel Register
            //==========================================================================
            // Normal: update on MUXON↓ (conversion start) — latch cur_ch_sel from
            //         the current FSM state (LP or HP).
            // Preempt: update on preempt_abort — latch hp_ch_sel directly because
            //         the FSM hasn't yet transitioned to HP state but the HP SOC
            //         is about to fire. hp_seq_ptr is always 0 at preemption time
            //         (reset after prior HP sequence completes).
            // Preempt hold: locks ch_sel after preempt_abort, released by muxon_fall.
            // Prevents muxon_fall from overwriting ch_sel_reg back to lp_ch_sel
            // after preempt_abort set it to hp_ch_sel.
            reg preempt_hold;
            always @(posedge adc_clk or negedge rst_adc_n) begin
                if (!rst_adc_n) begin
                    preempt_hold <= 1'b0;
                end else if (preempt_abort) begin
                    preempt_hold <= 1'b1;
                end else if (muxon_fall) begin
                    preempt_hold <= 1'b0;
                end
            end

            reg [W_CH_SEL-1:0] ch_sel_reg;
            always @(posedge adc_clk or negedge rst_adc_n) begin
                if (!rst_adc_n) begin
                    ch_sel_reg <= {W_CH_SEL{1'b0}};
                end else if (preempt_abort) begin
                    // HP preemption: switch to HP channel before SOC fires
                    ch_sel_reg <= hp_ch_sel;
                end else if (muxon_fall && !preempt_hold) begin
                    // Normal channel advance (preempt-induced muxon_fall suppressed)
                    ch_sel_reg <= cur_ch_sel;
                end
            end

            assign ch_sel = ch_sel_reg;

            //==========================================================================
            // EOC Detection
            //==========================================================================
            // EOC is generated by analog on ADC_CLK falling edge.
            // Sample it on ADC_CLK rising edge with 2-stage sync.
            // seq logic
            always @(posedge adc_clk or negedge rst_adc_n) begin
                if (!rst_adc_n) begin
                    eoc_sync1 <= 1'b0;
                    eoc_sync2 <= 1'b0;
                end else begin
                    eoc_sync1 <= eoc;
                    eoc_sync2 <= eoc_sync1;
                end
            end

            // EOC is a single-cycle pulse — capture it when sync2 is high
            // and we're in WAIT_EOC state
            assign eoc_captured = eoc_sync2;

            //==========================================================================
            // ADC Data Capture and Alignment
            //==========================================================================
            // Pipeline: sample adc_data every cycle so that when eoc_captured fires
            // the output logic (ch_data_wr_din_r) uses the CURRENT conversion's data,
            // not the PREVIOUS cycle's stale adc_data_capt (NBA ordering issue).
            //
            // Without this pipeline:
            //   At posedge where eoc_captured=1:
            //     adc_data_capt <= adc_data  (NBA — takes effect NEXT cycle)
            //     data_aligned   = f(adc_data_capt)  ← uses OLD value (before NBA)
            //     ch_data_wr_din <= data_aligned     ← writes stale data to CH_DATA
            //   → CH_DATA gets previous conversion's data; first conversion gets 0.
            //
            // With the pipeline:
            //   adc_data_d1 tracks adc_data (any cycle where data is stable suffices).
            //   On eoc_captured: adc_data_capt <= adc_data_d1 → correct value.
            // seq logic: pipeline register (1-cycle delayed copy of adc_data)
            always @(posedge adc_clk or negedge rst_adc_n) begin
                if (!rst_adc_n) begin
                    adc_data_d1 <= {ADC_DATA_W{1'b0}};
                end else begin
                    adc_data_d1 <= adc_data;
                end
            end

            // seq logic: capture on EOC (use pipelined value)
            always @(posedge adc_clk or negedge rst_adc_n) begin
                if (!rst_adc_n) begin
                    adc_data_capt <= {ADC_DATA_W{1'b0}};
                end else if (eoc_captured) begin
                    adc_data_capt <= adc_data_d1;
                end
            end

            // Data alignment — DATA 寄存器域固定 16bit；ADC_DATA_W 可配（1~16）
            //   右对齐：ADC 在 [ADC_DATA_W-1:0]，高位 [15:ADC_DATA_W]=0
            //   左对齐：ADC 在 [15:16-ADC_DATA_W]，低位 [16-ADC_DATA_W-1:0]=0
            // combo logic
            always @(*) begin
                if (cfg_data_align) begin
                    // Left align: ADC data left-shifted to MSB
                    data_aligned = {adc_data_capt, {(DATA_FIELD_W-ADC_DATA_W){1'b0}}};
                end else begin
                    // Right align: ADC data in low bits, high bits zero
                    data_aligned = {{(DATA_FIELD_W-ADC_DATA_W){1'b0}}, adc_data_capt};
                end
            end

            //==========================================================================
            // Channel Select
            //==========================================================================
            // combo logic — driven by current priority's sequence pointer
            always @(*) begin
                if (fsm_curr_st == ST_HP_SAMPLE ||
                    fsm_curr_st == ST_HP_WAIT_EOC ||
                    fsm_curr_st == ST_HP_INTERVAL) begin
                    cur_ch_sel = hp_ch_sel;
                end else begin
                    cur_ch_sel = lp_ch_sel;
                end
            end

            // (ch_sel is now registered on MUXON falling edge -- see above)

            //==========================================================================
            // FSM State Register
            //==========================================================================
            // seq logic
            always @(posedge adc_clk or negedge rst_adc_n) begin
                if (!rst_adc_n) begin
                    fsm_curr_st <= ST_IDLE;
                end else begin
                    fsm_curr_st <= fsm_next_st;
                end
            end

            //==========================================================================
            // FSM Control Signals
            //==========================================================================

            //==========================================================================
            // FSM Next State Logic
            //==========================================================================
            // combo logic
            always @(*) begin
                fsm_next_st = fsm_curr_st;
                soc_req_set  = 1'b0;
                interval_cnt_en = 1'b0;
                preempt_abort   = 1'b0;

                case (fsm_curr_st)

                    ST_IDLE: begin
                        if (cfg_adc_en) begin
                            fsm_next_st = ST_WAIT_TRIG;
                        end
                    end

                    ST_WAIT_TRIG: begin
                        if (!cfg_adc_en) begin
                            fsm_next_st = ST_IDLE;
                        end else if (hp_trig_pulse) begin
                            // HP takes priority
                            soc_req_set = 1'b1;
                            fsm_next_st = ST_HP_SAMPLE;
                        end else if (lp_trig_pulse) begin
                            soc_req_set = 1'b1;
                            fsm_next_st = ST_LP_SAMPLE;
                        end
                    end

                    ST_LP_SAMPLE: begin
                        if (hp_trig_pulse) begin
                            // HP preemption
                            preempt_abort = 1'b1;
                            fsm_next_st = ST_LP_PREEMPT;
                        end else if (spt_done) begin
                            // Sampling finished, wait for EOC
                            fsm_next_st = ST_LP_WAIT_EOC;
                        end
                    end

                    ST_LP_WAIT_EOC: begin
                        if (hp_trig_pulse) begin
                            // HP preemption during EOC wait
                            preempt_abort = 1'b1;
                            fsm_next_st = ST_LP_PREEMPT;
                        end else if (eoc_captured) begin
                            // EOC received, start interval
                            interval_cnt_en = 1'b1;
                            fsm_next_st = ST_LP_INTERVAL;
                        end
                    end

                    ST_LP_INTERVAL: begin
                        interval_cnt_en = 1'b1;
                        if (hp_trig_pulse) begin
                            // HP preemption during interval
                            preempt_abort = 1'b1;
                            fsm_next_st = ST_LP_PREEMPT;
                        end else if (interval_done) begin
                            // Check if sequence is complete
                            if (lp_seq_ptr >= cfg_lp_seq_len - 1'b1) begin
                                // Sequence done
                                if (cfg_cont_mode) begin
                                    soc_req_set = 1'b1;
                                    fsm_next_st = ST_LP_SAMPLE;
                                end else begin
                                    fsm_next_st = ST_WAIT_TRIG;
                                end
                            end else begin
                                // Next channel
                                soc_req_set = 1'b1;
                                fsm_next_st = ST_LP_SAMPLE;
                            end
                        end
                    end

                    ST_HP_SAMPLE: begin
                        // First HP SOC: driven by preempt_soc_pend (set in
                        // ST_LP_PREEMPT, auto-cleared next cycle), so SOC fires
                        // 1 cycle after preempt_rst_n asserts — analog is reset
                        // before SOC arrives.
                        soc_req_set = preempt_soc_pend;
                        if (spt_done) begin
                            fsm_next_st = ST_HP_WAIT_EOC;
                        end
                    end

                    ST_HP_WAIT_EOC: begin
                        if (eoc_captured) begin
                            interval_cnt_en = 1'b1;
                            fsm_next_st = ST_HP_INTERVAL;
                        end
                    end

                    ST_HP_INTERVAL: begin
                        interval_cnt_en = 1'b1;
                        if (interval_done) begin
                            if (hp_seq_ptr >= cfg_hp_seq_len - 1'b1) begin
                                // HP sequence done
                                if (lp_save_ptr != {W_LP_SEQ_PTR{1'b1}}) begin
                                    // Resume LP from saved position (unchanged)
                                    soc_req_set = 1'b1;
                                    fsm_next_st = ST_LP_SAMPLE;
                                end else begin
                                    // No LP to resume
                                    if (cfg_cont_mode) begin
                                        soc_req_set = 1'b1;
                                        fsm_next_st = ST_HP_SAMPLE;
                                    end else begin
                                        fsm_next_st = ST_WAIT_TRIG;
                                    end
                                end
                            end else begin
                                // Next HP channel
                                soc_req_set = 1'b1;
                                fsm_next_st = ST_HP_SAMPLE;
                            end
                        end
                    end

                    ST_LP_PREEMPT: begin
                        // Transition to HP sampling — SOC fires from ST_HP_SAMPLE
                        // to ensure preempt_rst_n has already taken effect.
                        fsm_next_st = ST_HP_SAMPLE;
                    end

                    default: begin
                        fsm_next_st = ST_IDLE;
                    end

                endcase
            end

            //==========================================================================
            // FSM Output Logic (sequence pointers, counters, events)
            //==========================================================================
            // seq logic
            always @(posedge adc_clk or negedge rst_adc_n) begin
                if (!rst_adc_n) begin

                    lp_seq_ptr    <= {W_LP_SEQ_PTR{1'b0}};
                    hp_seq_ptr    <= {W_HP_SEQ_PTR{1'b0}};
                    lp_save_ptr   <= {W_LP_SEQ_PTR{1'b1}};  // all-1s = no save (sentinel)

                    lp_eoc_pulse_r      <= 1'b0;
                    lp_seq_done_pulse_r <= 1'b0;
                    hp_eoc_pulse_r      <= 1'b0;
                    hp_seq_done_pulse_r <= 1'b0;
                    hp_preempt_pulse_r  <= 1'b0;
                    preempt_soc_pend    <= 1'b0;

                    eoc_idx_r         <= {W_EOC_IDX{1'b0}};
                    lp_data_wr_en_r   <= {W_LP_DATA_WEN{1'b0}};
                    lp_data_wr_din_r  <= {DATA_FIELD_W{1'b0}};
                    hp_data_wr_en_r   <= {W_HP_DATA_WEN{1'b0}};
                    hp_data_wr_din_r  <= {DATA_FIELD_W{1'b0}};

                end else begin

                    // Default: clear single-cycle pulses
                    lp_eoc_pulse_r      <= 1'b0;
                    hp_eoc_pulse_r      <= 1'b0;
                    lp_seq_done_pulse_r <= 1'b0;
                    hp_seq_done_pulse_r <= 1'b0;
                    hp_preempt_pulse_r  <= 1'b0;
                    preempt_soc_pend    <= 1'b0;
                    lp_data_wr_en_r     <= {W_LP_DATA_WEN{1'b0}};
                    hp_data_wr_en_r     <= {W_HP_DATA_WEN{1'b0}};

                    case (fsm_curr_st)

                        ST_IDLE: begin
                            lp_seq_ptr <= {W_LP_SEQ_PTR{1'b0}};
                            hp_seq_ptr <= {W_HP_SEQ_PTR{1'b0}};
                            lp_save_ptr <= {W_LP_SEQ_PTR{1'b1}};
                        end

                        ST_WAIT_TRIG: begin
                            // Reset LP pointer on new LP trigger
                            if (lp_trig_pulse) begin
                                lp_seq_ptr <= {W_LP_SEQ_PTR{1'b0}};
                            end
                            // Reset HP pointer on new HP trigger
                            if (hp_trig_pulse) begin
                                hp_seq_ptr <= {W_HP_SEQ_PTR{1'b0}};
                            end
                        end

                        ST_LP_SAMPLE: begin
                            // SOC generated on ADC_CLKn rising edge
                            // SPT counter runs
                        end

                        ST_LP_WAIT_EOC: begin
                            if (eoc_captured) begin
                                // Capture seq_ptr as the EOC index for regfile.
                                eoc_idx_r <= lp_seq_ptr;
                                // Write LP slot lp_seq_ptr with aligned data.
                                // Use adc_data_d1 (pipeline of adc_data) to avoid
                                // the NBA ordering issue documented above.
                                lp_data_wr_en_r  <= {{(W_LP_DATA_WEN-1){1'b0}}, 1'b1} << lp_seq_ptr;
                                // Right align: {高位0, adc_data_d1}；左对齐: {adc_data_d1, 低位0}
                                lp_data_wr_din_r <= (cfg_data_align ?
                                                     {adc_data_d1, {(DATA_FIELD_W-ADC_DATA_W){1'b0}}} :
                                                     {{(DATA_FIELD_W-ADC_DATA_W){1'b0}}, adc_data_d1});
                                // LP EOC event
                                lp_eoc_pulse_r <= 1'b1;
                            end
                        end

                        ST_LP_INTERVAL: begin
                            if (interval_done) begin
                                if (lp_seq_ptr >= cfg_lp_seq_len - 1'b1) begin
                                    // LP sequence complete
                                    lp_seq_done_pulse_r <= 1'b1;
                                    lp_seq_ptr <= {W_LP_SEQ_PTR{1'b0}};
                                end else begin
                                    // Advance to next channel
                                    lp_seq_ptr <= lp_seq_ptr + 1'b1;
                                end
                            end
                        end

                        ST_HP_SAMPLE: begin
                        end

                        ST_HP_WAIT_EOC: begin
                            if (eoc_captured) begin
                                // Capture seq_ptr as the EOC index for regfile.
                                eoc_idx_r <= {{(W_EOC_IDX-W_HP_SEQ_PTR){1'b0}}, hp_seq_ptr};
                                // Write HP slot hp_seq_ptr.
                                hp_data_wr_en_r  <= {{(W_HP_DATA_WEN-1){1'b0}}, 1'b1} << hp_seq_ptr;
                                hp_data_wr_din_r <= (cfg_data_align ?
                                                     {adc_data_d1, {(DATA_FIELD_W-ADC_DATA_W){1'b0}}} :
                                                     {{(DATA_FIELD_W-ADC_DATA_W){1'b0}}, adc_data_d1});
                                hp_eoc_pulse_r <= 1'b1;
                            end
                        end

                        ST_HP_INTERVAL: begin
                            if (interval_done) begin
                                if (hp_seq_ptr >= cfg_hp_seq_len - 1'b1) begin
                                    // HP sequence complete
                                    hp_seq_done_pulse_r <= 1'b1;
                                    hp_seq_ptr <= {W_HP_SEQ_PTR{1'b0}};
                                end else begin
                                    hp_seq_ptr <= hp_seq_ptr + 1'b1;
                                end
                            end
                        end

                        ST_LP_PREEMPT: begin
                            // Save LP state: current pointer and channel
                            lp_save_ptr <= lp_seq_ptr;
                            hp_preempt_pulse_r <= 1'b1;
                            // Request first HP SOC (fires in ST_HP_SAMPLE via combo logic).
                            // Delayed from ST_LP_PREEMPT so preempt_rst_n takes effect first.
                            preempt_soc_pend <= 1'b1;
                        end

                        default: begin
                        end

                    endcase

                    // Resume LP after HP completes
                    if (fsm_curr_st == ST_HP_INTERVAL && interval_done && hp_seq_ptr >= cfg_hp_seq_len - 1'b1) begin
                        if (lp_save_ptr != {W_LP_SEQ_PTR{1'b1}}) begin
                            // Restore saved LP pointer (re-sample the interrupted channel)
                            lp_seq_ptr <= lp_save_ptr;
                            lp_save_ptr <= {W_LP_SEQ_PTR{1'b1}};
                        end
                    end

                end
            end

            //==========================================================================
            // Output Assignments
            //==========================================================================
            assign stat_adc_busy   = (fsm_curr_st != ST_IDLE);
            assign stat_lp_busy    = (fsm_curr_st == ST_LP_SAMPLE ||
                                      fsm_curr_st == ST_LP_WAIT_EOC ||
                                      fsm_curr_st == ST_LP_INTERVAL);
            assign stat_hp_busy    = (fsm_curr_st == ST_HP_SAMPLE ||
                                      fsm_curr_st == ST_HP_WAIT_EOC ||
                                      fsm_curr_st == ST_HP_INTERVAL);

            assign lp_data_wr_en  = lp_data_wr_en_r;
            assign lp_data_wr_din = lp_data_wr_din_r;
            assign hp_data_wr_en  = hp_data_wr_en_r;
            assign hp_data_wr_din = hp_data_wr_din_r;
            assign eoc_idx        = eoc_idx_r;

            assign lp_eoc_pulse      = lp_eoc_pulse_r;
            assign hp_eoc_pulse      = hp_eoc_pulse_r;
            assign lp_seq_done_pulse = lp_seq_done_pulse_r;
            assign hp_seq_done_pulse = hp_seq_done_pulse_r;
            assign hp_preempt_pulse  = hp_preempt_pulse_r;

            // preempt_rst_n: active-low pulse during preemption to reset analog
            assign preempt_rst_n     = (fsm_curr_st == ST_LP_PREEMPT) ? 1'b0 : 1'b1;

        end
    endgenerate

endmodule
