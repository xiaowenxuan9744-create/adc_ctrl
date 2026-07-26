//*********************** Module Header ***************************************
// Module        : adc_top
// Description   : ADC controller top-level integration
//                 Instantiates all sub-modules and connects inter-module
//                 signals. Handles reset synchronization across clock domains.
// Clocks        : pclk, adc_clk, adc_clkn
// Reset         : presetn (PCLK domain), prstn (async for ADC domain)
// Parameters:
//   P_SHELL_MODE — 1 = shell mode, all outputs tied to safe values
//******************************************************************************
module adc_top #(
    parameter P_SHELL_MODE = 0,
    parameter ADC_NUM_CH = 26,
    parameter ADC_DATA_W = 14,
    parameter ADC_SPT1_CH_MASK = 32'h0060_0000
`include "adc_params.vh"
) (
    // APB interface
    input  wire        pclk,
    input  wire        presetn,
    input  wire [15:0] paddr,
    input  wire        pwrite,
    input  wire        psel,
    input  wire        penable,
    input  wire [31:0] pwdata,
    output wire [31:0] prdata,
    output wire        pready,
    output wire        pslverr,
    // ADC clocks and reset
    input  wire        adc_clk,
    input  wire        adc_clkn,
    input  wire        prstn,
    // Analog interface
    output wire        soc,
    output wire        muxon,
    output wire [$clog2(ADC_NUM_CH)-1:0] ch_sel,
    input  wire        eoc,
    input  wire [ADC_DATA_W-1:0] adc_data,
    // Calibration
    output wire        cal_st,
    input  wire        cal_done,
    input  wire [5:0]  cal_val,
    // External triggers (async)
    input  wire [5:0]  mctm_trig,
    // Interrupt and DMA
    output wire        adc_int,
    output wire        dma_ndreq,
    input  wire        dma_ack,

    // Analog reset (HP preempt: reset analog circuit per spec)
    output wire        preempt_rst_n
);
    `include "adc_params_check.vh"

    //==========================================================================
    // Internal Signals
    //==========================================================================
    // Reset domain
    wire rst_adc_n;
    // Software reset
    wire sw_rst_pulse;
    wire sw_rst_n;
    // APB IF → regfile
    wire       reg_wr_en;
    wire       reg_rd_en;
    wire [15:0] reg_addr;
    wire [31:0] wr_data;
    wire [31:0] rd_data;
    // regfile → other modules (ADC_CLK domain sync)
    wire        cfg_adc_en;
    wire [6:0]  cfg_smpl_interval;
    wire [2:0]  cfg_spt0;
    wire [2:0]  cfg_spt1;
    wire        cfg_data_align;
    wire [3:0]  cfg_lp_trg_sel;
    wire [3:0]  cfg_hp_trg_sel;
    wire        cfg_lp_mctm_en;
    wire        cfg_hp_mctm_en;
    wire        cfg_lp_sw_trg_en;
    wire        cfg_hp_sw_trg_en;
    wire        cfg_lp_sw_trig_raw;
    wire        cfg_hp_sw_trig_raw;
    wire [5:0]  cfg_int_en;
    wire        cfg_cal_st;      // PCLK-domain cal_st level → analog (direct)
    wire [5:0]  cfg_dma_ctrl;
    wire        cfg_dma_en;
    // LP/HP sequence entries：packed bus（entry i @ [i*W_CH_SEL +: W_CH_SEL]）
    wire [W_CH_SEL*ADC_NUM_CH-1:0] cfg_lp_seq_flat;
    wire [W_CH_SEL*4-1:0]          cfg_hp_seq_flat;
    wire        cfg_cont_mode;
    wire [W_LP_SEQ_LEN-1:0] cfg_lp_seq_len;
    wire [2:0]  cfg_hp_seq_len;
    // Trigger sync
    wire lp_trig_pulse;
    wire hp_trig_pulse;
    // FSM → regfile (LP_DATA / HP_DATA write + eoc_idx)
    wire [W_LP_DATA_WEN-1:0] lp_data_wr_en;
    wire [DATA_FIELD_W-1:0]  lp_data_wr_din;
    wire [W_HP_DATA_WEN-1:0] hp_data_wr_en;
    wire [DATA_FIELD_W-1:0]  hp_data_wr_din;
    wire [W_EOC_IDX-1:0]     eoc_idx;
    // FSM → status
    wire stat_adc_busy;
    wire stat_lp_busy;
    wire stat_hp_busy;
    // FSM → int_ctrl / dma_req
    wire lp_eoc_pulse;
    wire lp_seq_done_pulse;
    wire hp_eoc_pulse;
    wire hp_seq_done_pulse;
    wire hp_preempt_pulse;
    // int_ctrl → regfile
    wire [5:0] int_events;

    // cal_done/cal_val are analog inputs routed straight to the register file
    // (PCLK-domain sync + latch). cal_busy is derived in the regfile PCLK
    // domain (cal_st & ~cal_done_s2). No adc_calib instance is needed.
    // seq_fsm → analog (preempt reset)
    wire preempt_rst_n_int;
    //==========================================================================
    // Reset Synchronization
    //==========================================================================
    // Software reset pulse is AND-ed with PRSTn before the synchronizer.
    // In non-shell mode, both feed the same rst_sync.
    assign sw_rst_n = prstn & (~sw_rst_pulse);
    adc_rst_sync #(.P_SHELL_MODE(P_SHELL_MODE))
    u_rst_sync
    (
        .clk         (adc_clk   ),
        .async_rst_n (sw_rst_n  ),
        .sync_rst_n  (rst_adc_n )
    );
    //==========================================================================
    // APB Interface
    //==========================================================================
    adc_apb_if #(.P_SHELL_MODE(P_SHELL_MODE))
    u_apb_if
    (
        .PCLK       (pclk       ),
        .PRESETn    (presetn    ),
        .PADDR      (paddr      ),
        .PWRITE     (pwrite     ),
        .PSEL       (psel       ),
        .PENABLE    (penable    ),
        .PWDATA     (pwdata     ),
        .PRDATA     (prdata     ),
        .PREADY     (pready     ),
        .PSLVERR    (pslverr    ),
        .reg_wr_en  (reg_wr_en  ),
        .reg_rd_en  (reg_rd_en  ),
        .reg_addr   (reg_addr   ),
        .wr_data    (wr_data    ),
        .rd_data    (rd_data    )
    );
    //==========================================================================
    // Register File
    //==========================================================================
    adc_regfile #(.P_SHELL_MODE(P_SHELL_MODE),
                   .ADC_NUM_CH(ADC_NUM_CH), .ADC_DATA_W(ADC_DATA_W),
                   .ADC_SPT1_CH_MASK(ADC_SPT1_CH_MASK))
    u_regfile
    (
        .pclk       (pclk           ),
        .presetn    (presetn        ),
        .reg_wr_en  (reg_wr_en      ),
        .reg_rd_en  (reg_rd_en      ),
        .reg_addr   (reg_addr       ),
        .wr_data    (wr_data        ),
        .rd_data    (rd_data        ),
        .adc_clk    (adc_clk        ),
        .adc_clkn   (adc_clkn       ),
        .rst_adc_n  (rst_adc_n      ),
        .lp_data_wr_en   (lp_data_wr_en   ),
        .lp_data_wr_din  (lp_data_wr_din  ),
        .hp_data_wr_en   (hp_data_wr_en   ),
        .hp_data_wr_din  (hp_data_wr_din  ),
        .eoc_idx         (eoc_idx         ),
        .stat_adc_busy  (stat_adc_busy  ),
        .stat_lp_busy   (stat_lp_busy   ),
        .stat_hp_busy   (stat_hp_busy   ),
        .cal_done   (cal_done       ),
        .cal_val    (cal_val        ),
        .int_events (int_events     ),
        .adc_int    (adc_int        ),
        .cfg_adc_en         (cfg_adc_en         ),
        .cfg_smpl_interval  (cfg_smpl_interval  ),
        .cfg_spt0           (cfg_spt0           ),
        .cfg_spt1           (cfg_spt1           ),
        .cfg_data_align     (cfg_data_align     ),
        .cfg_lp_trg_sel     (cfg_lp_trg_sel     ),
        .cfg_hp_trg_sel     (cfg_hp_trg_sel     ),
        .cfg_lp_mctm_en     (cfg_lp_mctm_en     ),
        .cfg_hp_mctm_en     (cfg_hp_mctm_en     ),
        .cfg_lp_sw_trg_en   (cfg_lp_sw_trg_en   ),
        .cfg_hp_sw_trg_en   (cfg_hp_sw_trg_en   ),
        .cfg_lp_sw_trig_raw (cfg_lp_sw_trig_raw ),
        .cfg_hp_sw_trig_raw (cfg_hp_sw_trig_raw ),
        .cfg_cal_st         (cfg_cal_st         ),
        .cfg_dma_ctrl       (cfg_dma_ctrl       ),
        .cfg_dma_en         (cfg_dma_en         ),
        .cfg_lp_seq_flat    (cfg_lp_seq_flat    ),
        .cfg_hp_seq_flat    (cfg_hp_seq_flat    ),
        .cfg_cont_mode      (cfg_cont_mode      ),
        .cfg_lp_seq_len     (cfg_lp_seq_len     ),
        .cfg_hp_seq_len     (cfg_hp_seq_len     ),
        .sw_rst_pulse       (sw_rst_pulse       )
    );
    //==========================================================================
    // Trigger Synchronization
    //==========================================================================
    adc_trig_sync #(.P_SHELL_MODE(P_SHELL_MODE))
    u_trig_sync
    (
        .clk            (adc_clk        ),
        .rst_n          (rst_adc_n      ),
        .mctm_trig      (mctm_trig      ),
        .lp_trg_sel     (cfg_lp_trg_sel ),
        .hp_trg_sel     (cfg_hp_trg_sel ),
        .lp_mctm_en     (cfg_lp_mctm_en     ),
        .hp_mctm_en     (cfg_hp_mctm_en     ),
        .lp_sw_trg_en   (cfg_lp_sw_trg_en   ),
        .hp_sw_trg_en   (cfg_hp_sw_trg_en   ),
        .lp_sw_trig_raw (cfg_lp_sw_trig_raw ),
        .hp_sw_trig_raw (cfg_hp_sw_trig_raw ),
        .lp_trig_pulse  (lp_trig_pulse      ),
        .hp_trig_pulse  (hp_trig_pulse      )
    );
    //==========================================================================
    // Core Sequence FSM
    //==========================================================================
    adc_seq_fsm #(.P_SHELL_MODE(P_SHELL_MODE),
                   .ADC_NUM_CH(ADC_NUM_CH), .ADC_DATA_W(ADC_DATA_W),
                   .ADC_SPT1_CH_MASK(ADC_SPT1_CH_MASK))
    u_seq_fsm
    (
        .adc_clk            (adc_clk            ),
        .adc_clkn           (adc_clkn           ),
        .rst_adc_n          (rst_adc_n          ),
        .cfg_adc_en         (cfg_adc_en         ),
        .cfg_smpl_interval  (cfg_smpl_interval  ),
        .cfg_spt0           (cfg_spt0           ),
        .cfg_spt1           (cfg_spt1           ),
        .cfg_data_align     (cfg_data_align     ),
        .cfg_cont_mode      (cfg_cont_mode      ),
        .cfg_lp_seq_flat    (cfg_lp_seq_flat    ),
        .cfg_hp_seq_flat    (cfg_hp_seq_flat    ),
        .cfg_lp_seq_len     (cfg_lp_seq_len     ),
        .cfg_hp_seq_len     (cfg_hp_seq_len     ),
        .lp_trig_pulse      (lp_trig_pulse      ),
        .hp_trig_pulse      (hp_trig_pulse      ),
        .eoc                (eoc                ),
        .adc_data           (adc_data           ),
        .soc                (soc                ),
        .muxon              (muxon              ),
        .ch_sel             (ch_sel             ),
        .stat_adc_busy      (stat_adc_busy      ),
        .stat_lp_busy       (stat_lp_busy       ),
        .stat_hp_busy       (stat_hp_busy       ),
        .lp_data_wr_en      (lp_data_wr_en      ),
        .lp_data_wr_din     (lp_data_wr_din     ),
        .hp_data_wr_en      (hp_data_wr_en      ),
        .hp_data_wr_din     (hp_data_wr_din     ),
        .eoc_idx            (eoc_idx            ),
        .lp_eoc_pulse       (lp_eoc_pulse       ),
        .lp_seq_done_pulse  (lp_seq_done_pulse  ),
        .hp_eoc_pulse       (hp_eoc_pulse       ),
        .hp_seq_done_pulse  (hp_seq_done_pulse  ),
        .hp_preempt_pulse   (hp_preempt_pulse   ),
        .preempt_rst_n      (preempt_rst_n_int  )
    );
    //==========================================================================
    // Interrupt Controller
    //==========================================================================
    adc_int_ctrl #(.P_SHELL_MODE(P_SHELL_MODE))
    u_int_ctrl
    (
        .adc_clk            (adc_clk            ),
        .rst_adc_n          (rst_adc_n          ),
        .lp_eoc_pulse       (lp_eoc_pulse       ),
        .lp_seq_done_pulse  (lp_seq_done_pulse  ),
        .hp_eoc_pulse       (hp_eoc_pulse       ),
        .hp_seq_done_pulse  (hp_seq_done_pulse  ),
        .hp_preempt_pulse   (hp_preempt_pulse   ),

        .int_events         (int_events         )
    );
    //==========================================================================
    // DMA Request Controller
    //==========================================================================
    adc_dma_req #(.P_SHELL_MODE(P_SHELL_MODE))
    u_dma_req
    (
        .adc_clk            (adc_clk            ),
        .rst_adc_n          (rst_adc_n          ),
        .lp_eoc_pulse       (lp_eoc_pulse       ),
        .lp_seq_done_pulse  (lp_seq_done_pulse  ),
        .hp_eoc_pulse       (hp_eoc_pulse       ),
        .hp_seq_done_pulse  (hp_seq_done_pulse  ),
        .cfg_dma_en         (cfg_dma_en         ),
        .cfg_dma_ctrl       (cfg_dma_ctrl       ),
        .dma_ndreq          (dma_ndreq          ),
        .dma_ack            (dma_ack            )
    );
    // Analog preempt reset (from seq_fsm → output port)
    assign preempt_rst_n = preempt_rst_n_int;

    //==========================================================================
    // Calibration
    //==========================================================================
    // Calibration is now handled entirely in the register file (PCLK domain):
    //   - cal_st is a plain RW bit output via cfg_cal_st
    //   - cal_done is an analog input, 2-stage synced in regfile for CAL_CTRL[1]
    //     read and cal_val latch
    // No dedicated calibration controller module is needed.
    // Drive the analog CAL_ST output directly from the registered bit.
    // CAL_BUSY for STAT[3] is formed inside regfile from cal_st & ~cal_done_s2
    // (PCLK domain).
    assign cal_st    = cfg_cal_st;
endmodule
