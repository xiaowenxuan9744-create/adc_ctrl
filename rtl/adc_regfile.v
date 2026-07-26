//*********************** Module Header ***************************************
// Module        : adc_regfile
// Description   : ADC controller register file
//                 Dual clock domain design:
//                   - PCLK domain: APB-visible registers (CTRL, STAT, TRIG, etc.)
//                   - ADC_CLK domain: LP_DATA[0:25]/HP_DATA[0:3] storage +
//                     adc_en 2-stage sync; all other config signals are read
//                     directly from PCLK-domain registers (stable after ADC_EN
//                     sync completes — covered by SDC false_path).
//                 Register fields are declared individually per spec bitfield
//                 names (no _reg suffix). RSVD bits are not stored (hardcoded 0
//                 in readback). WO bits (TRIG LP_SW_TRIG / HP_SW_TRIG) are
//                 stored internally for trig_sync edge detection but read back
//                 as 0.
//                 Data registers are sequence-bound: LP_DATA[i] holds the i-th
//                 LP sequence slot's conversion result; HP_DATA[i] the i-th HP
//                 slot. The write index comes from seq_fsm (eoc_idx, = seq_ptr
//                 at the EOC cycle). VALID is a PCLK-domain per-slot flag set
//                 when the synchronized LP/HP EOC event arrives and cleared by
//                 APB read (local PCLK clear, no round-trip to ADC_CLK).
//                 Overflow is detected in PCLK at the same synced EOC edge: if
//                 the target slot's VALID is still 1, OVERRUN is raised.
// Clocks        : pclk, adc_clk
// Reset         : presetn (synchronous to pclk, active low)
//                 rst_adc_n (synchronous to adc_clk, active low)
// Parameters:
//   P_SHELL_MODE — 1 = shell mode, all outputs tied to safe values
//******************************************************************************
module adc_regfile #(
    parameter P_SHELL_MODE = 0,
    parameter ADC_NUM_CH = 26,
    parameter ADC_DATA_W = 14,
    parameter ADC_SPT1_CH_MASK = 32'h0060_0000
`include "adc_params.vh"
) (
    // PCLK domain
    input  wire        pclk,
    input  wire        presetn,
    input  wire        reg_wr_en,
    input  wire        reg_rd_en,
    input  wire [15:0] reg_addr,
    input  wire [31:0] wr_data,
    output wire [31:0] rd_data,

    // ADC_CLK domain
    input  wire        adc_clk,
    input  wire        adc_clkn,
    input  wire        rst_adc_n,

    // LP_DATA / HP_DATA write (from adc_seq_fsm, ADC_CLK domain)
    input  wire [W_LP_DATA_WEN-1:0] lp_data_wr_en,
    input  wire [DATA_FIELD_W-1:0]  lp_data_wr_din,
    input  wire [W_HP_DATA_WEN-1:0] hp_data_wr_en,
    input  wire [DATA_FIELD_W-1:0]  hp_data_wr_din,
    input  wire [W_EOC_IDX-1:0]     eoc_idx,        // seq_ptr captured at EOC (from seq_fsm)

    // Status write (from adc_seq_fsm, ADC_CLK domain)
    input  wire        stat_adc_busy,
    input  wire        stat_lp_busy,
    input  wire        stat_hp_busy,

    // Calibration (cal_done/cal_val analog inputs; cal_busy derived in PCLK)
    input  wire        cal_done,
    input  wire [5:0]  cal_val,

    // Interrupt events (from adc_int_ctrl, ADC_CLK domain, single-cycle pulse)
    //   [0] LP_EOC, [1] LP_SEQ_DONE, [2] HP_EOC, [3] HP_SEQ_DONE,
    //   [4] HP_PREEMPT.  [5] OVERRUN is generated in PCLK below.
    input  wire [5:0]  int_events,

    // Synchronized config outputs (to adc_seq_fsm, ADC_CLK domain)
    //   Only adc_en is synchronized; all other cfg_* outputs read PCLK-domain
    //   registers directly (stable between EOC events while ADC_EN is high).
    output wire        cfg_adc_en,
    output wire [6:0]  cfg_smpl_interval,
    output wire [2:0]  cfg_spt0,
    output wire [2:0]  cfg_spt1,
    output wire        cfg_data_align,
    output wire [3:0]  cfg_lp_trg_sel,
    output wire [3:0]  cfg_hp_trg_sel,
    output wire        cfg_lp_mctm_en,
    output wire        cfg_hp_mctm_en,
    output wire        cfg_lp_sw_trg_en,
    output wire        cfg_hp_sw_trg_en,
    output wire        cfg_lp_sw_trig_raw,  // PCLK-domain lp_sw_trig direct to trig_sync
    output wire        cfg_hp_sw_trig_raw,  // PCLK-domain hp_sw_trig direct to trig_sync
    output wire [5:0]  cfg_int_en,
    output wire        cfg_cal_st,      // PCLK-domain cal_st level -> analog (direct)
    output wire [5:0]  cfg_dma_ctrl,
    output wire        cfg_dma_en,
    // LP/HP sequence entries → seq_fsm：按 ch_sel 粒度 packed bus 传输。
    //   存储/传输位宽 = W_CH_SEL（rsv 高位不存、读回 0，APB 8bit 占位内只有效 ch_sel）
    //   cfg_lp_seq_flat: NUM_LP_DATA 个 W_CH_SEL-bit entry，entry i 在 [i*W_CH_SEL +: W_CH_SEL]
    //   cfg_hp_seq_flat: NUM_HP_DATA(=4) 个 W_CH_SEL-bit entry
    //   APB 边界仍按 32bit/组(4 entry × 8bit 占位) 读写，regfile 内拆/拼（rsv 补 0）。
    output wire [W_CH_SEL*NUM_LP_DATA-1:0] cfg_lp_seq_flat,
    output wire [W_CH_SEL*NUM_HP_DATA-1:0] cfg_hp_seq_flat,
    output wire        cfg_cont_mode,

    // Sequence length (to seq_fsm, ADC_CLK domain; direct PCLK reg read)
    output wire [W_LP_SEQ_LEN-1:0] cfg_lp_seq_len,
    output wire [2:0]              cfg_hp_seq_len,

    // Interrupt status clear (to int_ctrl, ADC_CLK domain, W1C from APB)
    output wire        adc_int,

    // Software reset pulse (PCLK domain)
    output wire        sw_rst_pulse
);
    `include "adc_params_check.vh"

    //==========================================================================
    // Shell Mode
    //==========================================================================
    generate
        if (P_SHELL_MODE) begin : gen_shell

            assign rd_data            = {32{1'b0}};
            assign cfg_adc_en         = 1'b0;
            assign cfg_smpl_interval  = 7'h0;
            assign cfg_spt0           = 3'h0;
            assign cfg_spt1           = 3'h0;
            assign cfg_data_align     = 1'b0;
            assign cfg_lp_trg_sel     = 4'h0;
            assign cfg_hp_trg_sel     = 4'h0;
            assign cfg_lp_mctm_en     = 1'b0;
            assign cfg_hp_mctm_en     = 1'b0;
            assign cfg_lp_sw_trg_en   = 1'b0;
            assign cfg_hp_sw_trg_en   = 1'b0;
            assign cfg_lp_sw_trig_raw = 1'b0;
            assign cfg_hp_sw_trig_raw = 1'b0;
            assign cfg_int_en         = 6'h00;
            assign cfg_cal_st         = 1'b0;
            assign cfg_dma_ctrl       = 6'h00;
            assign cfg_dma_en         = 1'b0;
            assign cfg_lp_seq_flat    = {(W_CH_SEL*NUM_LP_DATA){1'b0}};
            assign cfg_hp_seq_flat    = {(W_CH_SEL*NUM_HP_DATA){1'b0}};
            assign cfg_cont_mode      = 1'b0;
            assign cfg_lp_seq_len     = LP_SEQ_LEN_RST[W_LP_SEQ_LEN-1:0];
            assign cfg_hp_seq_len     = 3'd4;
            assign adc_int            = 1'b0;
            assign sw_rst_pulse       = 1'b0;

        end else begin : gen_active

            //==========================================================================
            // Internal Signals
            //==========================================================================

            // Address decode (word-aligned)
            wire [11:0] addr_offset;
            assign addr_offset = reg_addr[11:0] & 12'hFFC;

            // ----------------------------------------------------------------------
            // PCLK domain register storage — individual bitfields per spec §3.
            // RSVD bits are NOT stored; readback hardcodes them to 0.
            // WO bits (TRIG LP_SW_TRIG[0] / HP_SW_TRIG[8]) ARE stored internally
            // so the raw level can be forwarded to adc_trig_sync for edge detect,
            // but they read back as 0.
            // ----------------------------------------------------------------------

            // CTRL (0x00) — spec §3.2
            reg        adc_en;          // [0]
            reg        sw_rst;          // [1] SW_RST, write-1 self-clearing
            reg        data_align;      // [3]
            reg [2:0]  spt0;            // [10:8]
            reg [2:0]  spt1;            // [13:11]
            reg        cont_mode;       // [14]
            reg [6:0]  smpl_interval;   // [22:16]
            // RSVD: [2], [7:4], [15], [31:23]

            // TRIG (0x08) — spec §3.4
            reg        lp_sw_trig;      // [0]  WO — stored for edge detect, readback 0
            reg        lp_sw_trg_en;    // [1]
            reg        lp_mctm_en;      // [2]
            reg [3:0]  lp_trg_sel;      // [6:3]
            reg        hp_sw_trig;      // [8]  WO — stored for edge detect, readback 0
            reg        hp_sw_trg_en;    // [9]
            reg        hp_mctm_en;      // [10]
            reg [3:0]  hp_trg_sel;      // [14:11]
            // RSVD: [7], [15]

            // INT_EN (0x0C) — spec §3.5 (6-bit)
            reg [5:0]  int_en;
            // RSVD: [15:6]

            // INT_STAT (0x10) — spec §3.6 (6-bit W1C)
            reg [5:0]  int_stat;
            // RSVD: [15:6]

            // CAL_CTRL (0x14) — spec §3.7
            reg        cal_st;          // [0] RW
            // [1] CAL_DONE = cal_done_s2 (synced analog level, not stored)

            // CAL_VAL (0x18) — spec §3.8 (6-bit RO, latched from analog)
            reg [5:0]  cal_val_reg;
            // RSVD: [15:6]

            // ANA_CFG (0x1C) — spec §3.9 (16-bit RW)
            reg [15:0] ana_cfg;
            // RSVD: [31:16]

            // ANA_REG (0x20) — spec §3.10 (32-bit RW)
            reg [31:0] ana_reg;

            // DMA_CTRL (0xB4) — spec §3.12 (6-bit RW)
            reg [5:0]  dma_ctrl;
            // RSVD: [15:6]
            // DMA_STAT (0xA8) — DELETED per spec

            // LP_SEQ[0:7] (0xB8~0xD4) — spec §3.13
            // 地址空间固定按 8 组(32 seq)预留，内部按 ch_sel 粒度存储：
            // NUM_LP_DATA 个 W_CH_SEL-bit entry（每通道一个，rsv 高位不存）。
            // APB 8bit 占位内只有效低 W_CH_SEL bit，rsv 高位读回 0。
            // 超出 NUM_LP_DATA 的 entry 不实现，对应地址读回 0、写忽略。
            reg [W_CH_SEL-1:0] lp_seq_ent [0:NUM_LP_DATA-1];

            // HP_SEQ (0xD8) — spec §3.14 (4 entry × W_CH_SEL bit，APB 32bit 整读写，rsv 读 0)
            reg [W_CH_SEL-1:0] hp_seq_ent [0:NUM_HP_DATA-1];

            // LP_SEQ_LEN (0xDC) — spec §3.15 (W_LP_SEQ_LEN-bit RW, reset default ADC_NUM_CH)
            reg [W_LP_SEQ_LEN-1:0] lp_seq_len;
            // RSVD: [15:W_LP_SEQ_LEN]

            // HP_SEQ_LEN (0xE0) — spec §3.16 (3-bit RW, reset default 4)
            reg [2:0]  hp_seq_len;
            // RSVD: [15:3]

            // ----------------------------------------------------------------------
            // ADC_CLK domain: LP_DATA / HP_DATA storage (sequence-bound).
            // Data is written from seq_fsm on the EOC cycle. PCLK reads the
            // array directly (data is stable between EOC events for a given
            // slot — SDC false_path covers the PCLK→ADC_CLK array read).
            // ----------------------------------------------------------------------
            reg [DATA_FIELD_W-1:0] lp_data [0:NUM_LP_DATA-1];
            reg [DATA_FIELD_W-1:0] hp_data [0:NUM_HP_DATA-1];

            // ----------------------------------------------------------------------
            // PCLK domain: per-slot VALID flags + overflow detection.
            // Set when the synced LP/HP EOC edge arrives (int_evt_pclk_rise),
            // cleared by APB read of the corresponding slot (local PCLK clear).
            // ----------------------------------------------------------------------
            reg [NUM_LP_DATA-1:0] lp_valid_pclk;
            reg [NUM_HP_DATA-1:0] hp_valid_pclk;
            reg        overflow_event_pclk;  // single-cycle pulse → INT_STAT[5]

            // ----------------------------------------------------------------------
            // ADC_EN 2-stage sync (PCLK → ADC_CLK). This is the ONLY synced
            // config signal. All other cfg_* outputs read PCLK regs directly.
            // ----------------------------------------------------------------------
            reg        ctrl_adc_en_s1;
            reg        ctrl_adc_en_s2;

            // CAL_DONE sync (analog ADC_CLK level → PCLK, 2-stage) for CAL_CTRL[1]
            // read and cal_val latch. cal_st itself is a plain PCLK RW bit
            // output directly to analog — no CDC needed.
            reg        cal_done_s1;
            reg        cal_done_s2;

            // --- ADC_CLK → PCLK sync: interrupt events (2-stage + edge detect) ---
            // [5:1] come from int_events via int_ctrl; [0] LP_EOC and [2] HP_EOC
            // are also used to set lp_valid_pclk / hp_valid_pclk and detect
            // overflow in PCLK. The OVERRUN event [5] is NOT taken from
            // int_events — it is generated in PCLK below.
            reg [5:0]  int_evt_pclk_s1;
            reg [5:0]  int_evt_pclk_s2;
            reg [5:0]  int_evt_pclk_dly;
            wire [5:0] int_evt_pclk_rise;

            // --- ADC_CLK → PCLK sync: STAT busy bits (2-stage) ---
            reg        stat_adc_busy_s1;
            reg        stat_adc_busy_s2;
            reg        stat_lp_busy_s1;
            reg        stat_lp_busy_s2;
            reg        stat_hp_busy_s1;
            reg        stat_hp_busy_s2;
            // cal_busy is derived in PCLK (cal_st & ~cal_done_s2) — no ADC_CLK sync.

            // --- Software reset pulse detection ---
            reg        sw_rst_dly;
            wire       sw_rst_set;

            // Loop variable
            integer i;

            //==========================================================================
            // PCLK Domain: Address Decode helpers
            //==========================================================================
            wire is_lp_data;
            wire is_hp_data;
            wire is_lp_seq;
            wire is_hp_seq;
            reg [W_EOC_IDX-1:0] lp_data_idx;   // 0..NUM_LP_DATA-1
            reg [1:0]           hp_data_idx;   // 0..3
            reg [2:0]           lp_seq_idx;

            // LP_DATA: 0x24..0xA0（地址按 32 entry 预留；物理实现 NUM_LP_DATA 个，
            //   超出 idx 由 lp_data_idx<NUM_LP_DATA guard 读回 0、写忽略）
            assign is_lp_data = (addr_offset >= 12'h024) && (addr_offset <= 12'h0A0);
            // HP_DATA: 0xA4..0xB0（4 entry 固定）
            assign is_hp_data = (addr_offset >= 12'h0A4) && (addr_offset <= 12'h0B0);
            // LP_SEQ: 0xB8..0xD4（地址按 8 组预留；物理实现 NUM_LP_SEQ_REG 组，
            //   超出 entry 由 lp_seq_idx*4+k<NUM_LP_DATA guard 读回 0、写忽略）
            assign is_lp_seq   = (addr_offset >= 12'h0B8) && (addr_offset <= 12'h0D4);
            // HP_SEQ: 0xD8（4 entry 固定）
            assign is_hp_seq   = (addr_offset == 12'h0D8);

            always @(*) begin
                if (is_lp_data) begin
                    lp_data_idx = (addr_offset - 12'h024) >> 2;
                end else begin
                    lp_data_idx = {W_EOC_IDX{1'b0}};
                end
            end

            always @(*) begin
                if (is_hp_data) begin
                    hp_data_idx = (addr_offset - 12'h0A4) >> 2;
                end else begin
                    hp_data_idx = 2'h0;
                end
            end

            always @(*) begin
                if (is_lp_seq) begin
                    lp_seq_idx = (addr_offset - 12'h0B8) >> 2;
                end else begin
                    lp_seq_idx = 3'h0;
                end
            end

            //==========================================================================
            // PCLK Domain: Register Writes + INT_STAT + VALID/overflow + read-clear
            //==========================================================================
            // seq logic
            always @(posedge pclk or negedge presetn) begin
                if (!presetn) begin
                    // CTRL bitfields
                    adc_en         <= 1'b0;
                    sw_rst         <= 1'b0;
                    data_align     <= 1'b0;
                    spt0           <= 3'h0;
                    spt1           <= 3'h0;
                    cont_mode      <= 1'b0;
                    smpl_interval  <= 7'h00;
                    // TRIG bitfields
                    lp_sw_trig     <= 1'b0;
                    lp_sw_trg_en   <= 1'b0;
                    lp_mctm_en     <= 1'b0;
                    lp_trg_sel     <= 4'h0;
                    hp_sw_trig     <= 1'b0;
                    hp_sw_trg_en   <= 1'b0;
                    hp_mctm_en     <= 1'b0;
                    hp_trg_sel     <= 4'h0;
                    // INT
                    int_en         <= 6'h00;
                    int_stat       <= 6'h00;
                    // CAL
                    cal_st         <= 1'b0;
                    cal_val_reg    <= 6'h00;
                    cal_done_s1    <= 1'b0;
                    cal_done_s2    <= 1'b0;
                    // ANA
                    ana_cfg        <= 16'h0000;
                    ana_reg        <= 32'h00000000;
                    // DMA
                    dma_ctrl       <= 6'h00;
                    // SEQ (ch_sel 粒度复位)
                    for (i = 0; i < NUM_LP_DATA; i = i + 1) begin
                        lp_seq_ent[i] <= {W_CH_SEL{1'b0}};
                    end
                    for (i = 0; i < NUM_HP_DATA; i = i + 1) begin
                        hp_seq_ent[i] <= {W_CH_SEL{1'b0}};
                    end
                    lp_seq_len     <= LP_SEQ_LEN_RST[W_LP_SEQ_LEN-1:0];
                    hp_seq_len     <= 3'd4;
                    // SW_RST edge detect
                    sw_rst_dly     <= 1'b0;
                    // INT event sync
                    int_evt_pclk_s1  <= 6'h00;
                    int_evt_pclk_s2  <= 6'h00;
                    int_evt_pclk_dly <= 6'h00;
                    // VALID flags
                    lp_valid_pclk    <= {NUM_LP_DATA{1'b0}};
                    hp_valid_pclk    <= {NUM_HP_DATA{1'b0}};
                    overflow_event_pclk <= 1'b0;
                end else begin

                    // CAL_DONE sync (analog ADC_CLK level → PCLK, 2-stage)
                    cal_done_s1 <= cal_done;
                    cal_done_s2 <= cal_done_s1;

                    // SW_RST edge detection
                    sw_rst_dly <= sw_rst;

                    // SW_RST self-clear: after generating the pulse, clear the bit
                    if (sw_rst_set) begin
                        sw_rst <= 1'b0;
                    end

                    // SW_RST resets all PCLK domain registers except adc_en
                    // (matches legacy behavior).
                    if (sw_rst_set) begin
                        data_align     <= 1'b0;
                        spt0           <= 3'h0;
                        spt1           <= 3'h0;
                        cont_mode      <= 1'b0;
                        smpl_interval  <= 7'h00;
                        lp_sw_trig     <= 1'b0;
                        lp_sw_trg_en   <= 1'b0;
                        lp_mctm_en     <= 1'b0;
                        lp_trg_sel     <= 4'h0;
                        hp_sw_trig     <= 1'b0;
                        hp_sw_trg_en   <= 1'b0;
                        hp_mctm_en     <= 1'b0;
                        hp_trg_sel     <= 4'h0;
                        int_en         <= 6'h00;
                        int_stat       <= 6'h00;
                        cal_st         <= 1'b0;
                        cal_val_reg    <= 6'h00;
                        ana_cfg        <= 16'h0000;
                        ana_reg        <= 32'h00000000;
                        dma_ctrl       <= 6'h00;
                        lp_valid_pclk  <= {NUM_LP_DATA{1'b0}};
                        hp_valid_pclk  <= {NUM_HP_DATA{1'b0}};
                        int_evt_pclk_s1  <= 6'h00;
                        int_evt_pclk_s2  <= 6'h00;
                        int_evt_pclk_dly <= 6'h00;
                        for (i = 0; i < NUM_LP_DATA; i = i + 1) begin
                            lp_seq_ent[i]  <= {W_CH_SEL{1'b0}};
                        end
                        for (i = 0; i < NUM_HP_DATA; i = i + 1) begin
                            hp_seq_ent[i]  <= {W_CH_SEL{1'b0}};
                        end
                        lp_seq_len     <= LP_SEQ_LEN_RST[W_LP_SEQ_LEN-1:0];
                        hp_seq_len     <= 3'd4;
                    end

                    // --------------------------------------------------------------
                    // INT_STAT update:
                    //   bits [4:0] from synced ADC_CLK int_events (rising edge)
                    //   bit [5] OVERRUN from PCLK-local overflow_event_pclk
                    // --------------------------------------------------------------
                    int_stat[4:0] <= (int_stat[4:0] | int_evt_pclk_rise[4:0]);
                    if (overflow_event_pclk) begin
                        int_stat[5] <= 1'b1;
                    end

                    // --------------------------------------------------------------
                    // LP/HP VALID set + overflow detection (PCLK domain, on synced
                    // LP_EOC / HP_EOC rising edge). eoc_idx is stable by the time
                    // the edge arrives (set at EOC cycle in ADC_CLK domain, ~2
                    // adc_clk + 2 pclk earlier).
                    // --------------------------------------------------------------
                    overflow_event_pclk <= 1'b0;  // default
                    if (int_evt_pclk_rise[0]) begin
                        // LP EOC arrived
                        if (eoc_idx < NUM_LP_DATA) begin
                            if (lp_valid_pclk[eoc_idx]) begin
                                overflow_event_pclk <= 1'b1;
                            end
                            lp_valid_pclk[eoc_idx] <= 1'b1;
                        end
                    end
                    if (int_evt_pclk_rise[2]) begin
                        // HP EOC arrived
                        if (eoc_idx < NUM_HP_DATA) begin
                            if (hp_valid_pclk[eoc_idx]) begin
                                overflow_event_pclk <= 1'b1;
                            end
                            hp_valid_pclk[eoc_idx] <= 1'b1;
                        end
                    end

                    // --------------------------------------------------------------
                    // APB read-clear for LP_DATA / HP_DATA (local PCLK clear)
                    // --------------------------------------------------------------
                    if (reg_rd_en && is_lp_data && (lp_data_idx < NUM_LP_DATA)) begin
                        lp_valid_pclk[lp_data_idx] <= 1'b0;
                    end
                    if (reg_rd_en && is_hp_data) begin
                        hp_valid_pclk[hp_data_idx] <= 1'b0;
                    end

                    // --------------------------------------------------------------
                    // Register write decode
                    // --------------------------------------------------------------
                    if (reg_wr_en) begin
                        case (addr_offset)
                            12'h000: begin
                                // CTRL — spec §3.2
                                adc_en        <= wr_data[0];
                                sw_rst        <= wr_data[1];
                                data_align    <= wr_data[3];
                                spt0          <= wr_data[10:8];
                                spt1          <= wr_data[13:11];
                                cont_mode     <= wr_data[14];
                                smpl_interval <= wr_data[22:16];
                            end

                            12'h008: begin
                                // TRIG — spec §3.4. bit0/bit8 are WO (stored for
                                // edge detect, readback 0).
                                lp_sw_trig   <= wr_data[0];
                                lp_sw_trg_en <= wr_data[1];
                                lp_mctm_en   <= wr_data[2];
                                lp_trg_sel   <= wr_data[6:3];
                                hp_sw_trig   <= wr_data[8];
                                hp_sw_trg_en <= wr_data[9];
                                hp_mctm_en   <= wr_data[10];
                                hp_trg_sel   <= wr_data[14:11];
                            end

                            12'h00C: begin
                                // INT_EN — spec §3.5 (6-bit)
                                int_en <= wr_data[5:0];
                            end

                            12'h010: begin
                                // INT_STAT — spec §3.6 W1C: write 1 to clear
                                if (wr_data[0]) int_stat[0] <= 1'b0;
                                if (wr_data[1]) int_stat[1] <= 1'b0;
                                if (wr_data[2]) int_stat[2] <= 1'b0;
                                if (wr_data[3]) int_stat[3] <= 1'b0;
                                if (wr_data[4]) int_stat[4] <= 1'b0;
                                if (wr_data[5]) int_stat[5] <= 1'b0;
                            end

                            12'h014: begin
                                // CAL_CTRL — spec §3.7. CAL_ST (bit 0): plain PCLK
                                // RW bit. Output directly to analog.
                                cal_st <= wr_data[0];
                            end

                            12'h01C: begin
                                // ANA_CFG — spec §3.9 (16-bit RW)
                                ana_cfg <= wr_data[15:0];
                            end

                            12'h020: begin
                                // ANA_REG — spec §3.10 (32-bit RW)
                                ana_reg <= wr_data;
                            end

                            12'h0B4: begin
                                // DMA_CTRL — spec §3.12 (6-bit RW)
                                dma_ctrl <= wr_data[5:0];
                            end

                            12'h0DC: begin
                                // LP_SEQ_LEN — spec §3.15 (W_LP_SEQ_LEN-bit RW)
                                lp_seq_len <= wr_data[W_LP_SEQ_LEN-1:0];
                            end

                            12'h0E0: begin
                                // HP_SEQ_LEN — spec §3.16 (3-bit RW)
                                hp_seq_len <= wr_data[2:0];
                            end

                            default: begin
                                // LP_SEQ (0xB8~0xD4) — spec §3.13
                                // 拆 32bit(4×8bit 占位) → 4 ch_sel；每个 8bit 占位只取低 W_CH_SEL bit
                                // 全局 entry idx = lp_seq_idx*4 + k；只写落在 0..NUM_LP_DATA-1 的 entry
                                if (is_lp_seq) begin
                                    if (lp_seq_idx*4 + 0 < NUM_LP_DATA) lp_seq_ent[lp_seq_idx*4 + 0] <= wr_data[0*8 +: W_CH_SEL];
                                    if (lp_seq_idx*4 + 1 < NUM_LP_DATA) lp_seq_ent[lp_seq_idx*4 + 1] <= wr_data[1*8 +: W_CH_SEL];
                                    if (lp_seq_idx*4 + 2 < NUM_LP_DATA) lp_seq_ent[lp_seq_idx*4 + 2] <= wr_data[2*8 +: W_CH_SEL];
                                    if (lp_seq_idx*4 + 3 < NUM_LP_DATA) lp_seq_ent[lp_seq_idx*4 + 3] <= wr_data[3*8 +: W_CH_SEL];
                                end
                                // HP_SEQ (0xD8) — spec §3.14 (4 × W_CH_SEL bit，APB 32bit 整读写)
                                if (is_hp_seq) begin
                                    hp_seq_ent[0] <= wr_data[0*8 +: W_CH_SEL];
                                    hp_seq_ent[1] <= wr_data[1*8 +: W_CH_SEL];
                                    hp_seq_ent[2] <= wr_data[2*8 +: W_CH_SEL];
                                    hp_seq_ent[3] <= wr_data[3*8 +: W_CH_SEL];
                                end
                            end
                        endcase
                    end

                    // CAL_VAL: latch when synchronized CAL_DONE is 1.
                    if (cal_done_s2) begin
                        cal_val_reg <= cal_val;
                    end

                    // Interrupt event sync: ADC_CLK → PCLK (2-stage direct).
                    // int_events comes from ADC_CLK domain (int_ctrl). Sync directly
                    // in PCLK domain — do NOT pre-sync in ADC_CLK (that adds 2 extra
                    // stages and delays edge detection).
                    int_evt_pclk_s1  <= int_events;
                    int_evt_pclk_s2  <= int_evt_pclk_s1;
                    int_evt_pclk_dly <= int_evt_pclk_s2;
                end
            end

            // Interrupt event rising edge (PCLK domain)
            assign int_evt_pclk_rise = int_evt_pclk_s2 & (~int_evt_pclk_dly);

            // Software reset pulse: rising edge of sw_rst bitfield
            assign sw_rst_set  = sw_rst & (~sw_rst_dly);
            assign sw_rst_pulse = sw_rst_set;

            // Level interrupt output: OR of ENABLED status bits (PCLK domain)
            assign adc_int = |(int_stat & int_en);

            //==========================================================================
            // PCLK Domain: Register Read Mux
            //==========================================================================
            // combo logic: read mux assembles 32-bit per spec bit positions.
            // RSVD bits return 0; WO bits (TRIG[0]/[8]) return 0.
            reg [31:0] rd_data_mux;
            always @(*) begin  // iverilog warning: @* sensitive to all array words — expected
                rd_data_mux = {32{1'b0}};
                case (addr_offset)
                    // CTRL (0x00): {9'h0, smpl_interval, 1'b0, cont_mode, spt1, spt0, 4'h0, data_align, 1'b0, sw_rst, adc_en}
                    12'h000: rd_data_mux = {9'h000, smpl_interval, 1'b0, cont_mode,
                                             spt1, spt0, 4'h0, data_align, 1'b0,
                                             sw_rst, adc_en};
                    // STAT (0x04): {16'h0, 12'h0, cal_busy, hp_busy, lp_busy, adc_busy}
                    //   cal_busy = cal_st & ~cal_done_s2 (PCLK combinational)
                    12'h004: rd_data_mux = {16'h0000, 12'h000,
                                            (cal_st & ~cal_done_s2),
                                            stat_hp_busy_s2, stat_lp_busy_s2,
                                            stat_adc_busy_s2};
                    // TRIG (0x08): bit15 RSVD, bit8/bit0 WO → 0, bit7 RSVD.
                    12'h008: rd_data_mux = {1'b0, hp_trg_sel, hp_mctm_en,
                                            hp_sw_trg_en, 1'b0, 1'b0, lp_trg_sel,
                                            lp_mctm_en, lp_sw_trg_en, 1'b0};
                    // INT_EN (0x0C): {10'h0, int_en}
                    12'h00C: rd_data_mux = {10'h000, int_en};
                    // INT_STAT (0x10): {10'h0, int_stat}
                    12'h010: rd_data_mux = {10'h000, int_stat};
                    // CAL_CTRL (0x14): {14'h0, cal_done_s2, cal_st}
                    12'h014: rd_data_mux = {14'h0000, cal_done_s2, cal_st};
                    // CAL_VAL (0x18): {10'h0, cal_val_reg}
                    12'h018: rd_data_mux = {10'h000, cal_val_reg};
                    // ANA_CFG (0x1C): {16'h0, ana_cfg}
                    12'h01C: rd_data_mux = {16'h0000, ana_cfg};
                    // ANA_REG (0x20): ana_reg (full 32-bit)
                    12'h020: rd_data_mux = ana_reg;
                    // DMA_CTRL (0xB4): {10'h0, dma_ctrl}
                    12'h0B4: rd_data_mux = {10'h000, dma_ctrl};
                    // LP_SEQ_LEN (0xDC): {高位0, lp_seq_len}
                    12'h0DC: rd_data_mux = {{(16-W_LP_SEQ_LEN){1'b0}}, lp_seq_len};
                    // HP_SEQ_LEN (0xE0): {13'h0, hp_seq_len}
                    12'h0E0: rd_data_mux = {13'h0000, hp_seq_len};
                    default: begin
                        if (is_lp_data) begin
                            // LP_DATA read: {VALID, 15'h0, DATA}
                            //   lp_data lives in ADC_CLK domain but is stable
                            //   between EOC events for a given slot.
                            if (lp_data_idx < NUM_LP_DATA) begin
                                rd_data_mux = {lp_valid_pclk[lp_data_idx], 15'h0000,
                                               lp_data[lp_data_idx]};
                            end
                            // lp_data_idx >= NUM_LP_DATA (reserved): reads 0
                        end else if (is_hp_data) begin
                            rd_data_mux = {hp_valid_pclk[hp_data_idx], 15'h0000,
                                           hp_data[hp_data_idx]};
                        end else if (is_lp_seq) begin
                            // 拼 4 ch_sel → 32bit(4×8bit 占位)；每 entry 零扩展到 8bit（rsv 高位补 0）
                            // 超出 NUM_LP_DATA 的 entry 读 0
                            rd_data_mux = {
                                (lp_seq_idx*4 + 3 < NUM_LP_DATA) ? {{(8-W_CH_SEL){1'b0}}, lp_seq_ent[lp_seq_idx*4 + 3]} : 8'h00,
                                (lp_seq_idx*4 + 2 < NUM_LP_DATA) ? {{(8-W_CH_SEL){1'b0}}, lp_seq_ent[lp_seq_idx*4 + 2]} : 8'h00,
                                (lp_seq_idx*4 + 1 < NUM_LP_DATA) ? {{(8-W_CH_SEL){1'b0}}, lp_seq_ent[lp_seq_idx*4 + 1]} : 8'h00,
                                (lp_seq_idx*4 + 0 < NUM_LP_DATA) ? {{(8-W_CH_SEL){1'b0}}, lp_seq_ent[lp_seq_idx*4 + 0]} : 8'h00
                            };
                        end else if (is_hp_seq) begin
                            rd_data_mux = {
                                {{(8-W_CH_SEL){1'b0}}, hp_seq_ent[3]},
                                {{(8-W_CH_SEL){1'b0}}, hp_seq_ent[2]},
                                {{(8-W_CH_SEL){1'b0}}, hp_seq_ent[1]},
                                {{(8-W_CH_SEL){1'b0}}, hp_seq_ent[0]}
                            };
                        end
                    end
                endcase
            end

            assign rd_data = rd_data_mux;

            //==========================================================================
            // ADC_CLK Domain: Configuration Synchronization (PCLK → ADC_CLK)
            //   Only adc_en is synced (2-stage). All other cfg_* outputs read
            //   PCLK-domain registers directly — stable between EOC events while
            //   ADC_EN is high. SDC false_path covers these crossings.
            //==========================================================================
            always @(posedge adc_clk or negedge rst_adc_n) begin
                if (!rst_adc_n) begin
                    ctrl_adc_en_s1 <= 1'b0;
                    ctrl_adc_en_s2 <= 1'b0;
                end else begin
                    ctrl_adc_en_s1 <= adc_en;
                    ctrl_adc_en_s2 <= ctrl_adc_en_s1;
                end
            end

            // Synchronized config outputs (ADC_CLK domain). adc_en is synced;
            // all other cfg_* read PCLK-domain reg directly (async read, stable
            // between EOC events — SDC false_path).
            assign cfg_adc_en         = ctrl_adc_en_s2;
            assign cfg_smpl_interval  = smpl_interval;
            assign cfg_spt0           = spt0;
            assign cfg_spt1           = spt1;
            assign cfg_data_align     = data_align;
            assign cfg_lp_trg_sel     = lp_trg_sel;
            assign cfg_hp_trg_sel     = hp_trg_sel;
            assign cfg_lp_mctm_en     = lp_mctm_en;
            assign cfg_hp_mctm_en     = hp_mctm_en;
            assign cfg_lp_sw_trg_en   = lp_sw_trg_en;
            assign cfg_hp_sw_trg_en   = hp_sw_trg_en;
            // SW_TRIG raw: PCLK-domain reg direct to trig_sync (trig_sync has
            // its own sync_cell + edge detect).
            assign cfg_lp_sw_trig_raw = lp_sw_trig;
            assign cfg_hp_sw_trig_raw = hp_sw_trig;
            assign cfg_int_en         = int_en;
            assign cfg_cal_st         = cal_st;  // PCLK RW bit, direct to analog
            assign cfg_dma_ctrl       = dma_ctrl;
            assign cfg_dma_en         = dma_ctrl[0];
            // LP/HP_SEQ → seq_fsm：N 个 ch_sel 拼成 packed bus，entry i 在 [i*W_CH_SEL +: W_CH_SEL]。
            // generate 内 part-select 左值 assign（iverilog -g2012 / VCS 支持）。
            genvar ei;
            for (ei = 0; ei < NUM_LP_DATA; ei = ei + 1) begin : gen_lp_seq_flat
                assign cfg_lp_seq_flat[ei*W_CH_SEL +: W_CH_SEL] = lp_seq_ent[ei];
            end
            for (ei = 0; ei < NUM_HP_DATA; ei = ei + 1) begin : gen_hp_seq_flat
                assign cfg_hp_seq_flat[ei*W_CH_SEL +: W_CH_SEL] = hp_seq_ent[ei];
            end
            assign cfg_cont_mode      = cont_mode;
            assign cfg_lp_seq_len     = lp_seq_len;
            assign cfg_hp_seq_len     = hp_seq_len;

            //==========================================================================
            // ADC_CLK Domain: LP_DATA / HP_DATA write (from seq_fsm)
            //==========================================================================
            always @(posedge adc_clk or negedge rst_adc_n) begin
                if (!rst_adc_n) begin
                    for (i = 0; i < NUM_LP_DATA; i = i + 1) begin
                        lp_data[i] <= {DATA_FIELD_W{1'b0}};
                    end
                    for (i = 0; i < NUM_HP_DATA; i = i + 1) begin
                        hp_data[i] <= {DATA_FIELD_W{1'b0}};
                    end
                end else begin
                    for (i = 0; i < NUM_LP_DATA; i = i + 1) begin
                        if (lp_data_wr_en[i]) begin
                            lp_data[i] <= lp_data_wr_din[DATA_FIELD_W-1:0];
                        end
                    end
                    for (i = 0; i < NUM_HP_DATA; i = i + 1) begin
                        if (hp_data_wr_en[i]) begin
                            hp_data[i] <= hp_data_wr_din[DATA_FIELD_W-1:0];
                        end
                    end
                end
            end

            //==========================================================================
            // ADC_CLK Domain: Status Synchronization (ADC_CLK → PCLK)
            //   stat_*_busy come from seq_fsm (ADC_CLK domain) and are 2-stage
            //   synced into PCLK here. cal_done/cal_val are analog inputs synced
            //   in the PCLK block above. OVERRUN is generated in PCLK (not here).
            //==========================================================================
            always @(posedge adc_clk or negedge rst_adc_n) begin
                if (!rst_adc_n) begin
                    stat_adc_busy_s1 <= 1'b0;
                    stat_adc_busy_s2 <= 1'b0;
                    stat_lp_busy_s1  <= 1'b0;
                    stat_lp_busy_s2  <= 1'b0;
                    stat_hp_busy_s1  <= 1'b0;
                    stat_hp_busy_s2  <= 1'b0;
                end else begin
                    stat_adc_busy_s1 <= stat_adc_busy;
                    stat_adc_busy_s2 <= stat_adc_busy_s1;

                    stat_lp_busy_s1  <= stat_lp_busy;
                    stat_lp_busy_s2  <= stat_lp_busy_s1;

                    stat_hp_busy_s1  <= stat_hp_busy;
                    stat_hp_busy_s2  <= stat_hp_busy_s1;

                    // int_evt_s1/s2 removed — int_events is now synced directly
                    // in the PCLK domain (int_evt_pclk_s1/s2). No ADC_CLK pre-sync.
                end
            end

        end
    endgenerate

endmodule
