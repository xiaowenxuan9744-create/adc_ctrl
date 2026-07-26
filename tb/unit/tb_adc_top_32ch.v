//*********************** Testbench Header ************************************
// Testbench     : tb_adc_top_32ch
// Description   : 32 通道 / 14bit 参数化配置 smoke testbench
//                 闭合 b75842f 验证缺口：N=27~32 时 LP_DATA[26:31]（地址
//                 0x8C~0xA0）读回有效。b75842f 修复前 is_lp_data 上界硬编码
//                 0x088，N>=27 时这些地址落在范围外 → default → 读回 0；修复后
//                 上界 0x0A0 + lp_data_idx<NUM_LP_DATA guard，覆盖完整 32 预留区。
//                 验证 ADC_NUM_CH=32 / ADC_DATA_W=14 / SPT1 mask=0 配置下：
//                 - ch_sel 5bit / LP_DATA 32 个 / LP_SEQ 8 组 / LP_SEQ_LEN 6bit
//                 - 32 条目 LP 序列扫描后 LP_DATA[0:31] 全 VALID + data 正确
//                 - 重点断言 LP_DATA[26:31] @0x8C~0xA0（b75842f 地址）读回有效
//                 - 0xA0/0xA4 边界、LP_SEQ7 @0xD4、entry rsv 高位读回 0、LP_SEQ_LEN 6bit RW
//                 聚焦 b75842f 缺口，不做全回归（中断/校准/sw复位/DMA/抢占由 26ch+8ch TB 覆盖）
// DUT           : adc_top (ADC_NUM_CH=32, ADC_DATA_W=14)
//******************************************************************************

`timescale 1ns / 1ps

//==========================================================================
// 参数化 smoke 配置：32 通道 / 14bit / SPT1 mask=0（全 SPT0）
// 派生 localparam 在 adc_top 实例化的 #(...) 内 include adc_params.vh 取得
//==========================================================================
localparam int TB_ADC_NUM_CH       = 32;
localparam int TB_ADC_DATA_W       = 14;
localparam int TB_ADC_SPT1_CH_MASK = 32'h0000_0000;

module tb_adc_top_32ch;

    //==========================================================================
    // Parameters
    //==========================================================================
    parameter PCLK_PERIOD = 20;       // 50 MHz APB
    parameter ADCCLK_PERIOD = 40;     // 25 MHz ADC clock

    //==========================================================================
    // Signals
    //==========================================================================
    reg         pclk;
    reg         presetn;
    reg  [15:0] paddr;
    reg         pwrite;
    reg         psel;
    reg         penable;
    reg  [31:0] pwdata;
    wire [31:0] prdata;
    wire        pready;
    wire        pslverr;

    reg         adc_clk;
    reg         adc_clkn;
    reg         prstn;

    wire        soc;
    wire        muxon;
    wire [$clog2(TB_ADC_NUM_CH)-1:0]  ch_sel;
    wire        eoc;
    wire [TB_ADC_DATA_W-1:0] adc_data;

    wire        cal_st;
    wire        cal_done;
    wire [5:0]  cal_val;

    reg  [5:0]  mctm_trig;

    wire        adc_int;
    wire        dma_ndreq;
    wire        preempt_rst_n;
    reg         dma_ack = 1'b0;

    //==========================================================================
    // Test control
    //==========================================================================
    integer pass, fail;
    reg all_done;
    reg [31:0] got, expected;

    // Expected sample data per channel (captured on EOC rising edge at posedge adc_clk)
    reg [TB_ADC_DATA_W-1:0] exp_data [0:31];
    reg        eoc_dly;
    always @(posedge adc_clk) begin
        eoc_dly <= eoc;
        if (!eoc_dly && eoc) begin  // EOC rising edge
            exp_data[ch_sel] <= adc_data;
            $display("[CAPTURE] @%0t ch_sel=%0d adc_data=0x%04h", $time, ch_sel, adc_data);
        end
    end

    // Register address map (from spec)
    localparam ADDR_CTRL      = 16'h0000;
    localparam ADDR_STAT      = 16'h0004;
    localparam ADDR_TRIG      = 16'h0008;
    localparam ADDR_INT_EN    = 16'h000C;
    localparam ADDR_INT_STAT  = 16'h0010;
    localparam ADDR_CAL_CTRL  = 16'h0014;
    localparam ADDR_CAL_VAL   = 16'h0018;
    localparam ADDR_ANA_CFG   = 16'h001C;
    localparam ADDR_ANA_REG   = 16'h0020;
    localparam ADDR_LP_DATA0  = 16'h0024;
    localparam ADDR_HP_DATA0  = 16'h00A4;
    localparam ADDR_DMA_CTRL  = 16'h00B4;
    localparam ADDR_LP_SEQ0   = 16'h00B8;
    localparam ADDR_LP_SEQ_LEN = 16'h00DC;
    localparam ADDR_HP_SEQ    = 16'h00D8;
    localparam ADDR_HP_SEQ_LEN = 16'h00E0;

    //==========================================================================
    // DUT Instantiation
    //==========================================================================
    adc_top #(.P_SHELL_MODE(0),
              .ADC_NUM_CH(TB_ADC_NUM_CH), .ADC_DATA_W(TB_ADC_DATA_W),
              .ADC_SPT1_CH_MASK(TB_ADC_SPT1_CH_MASK))
    u_dut
    (
        .pclk       (pclk       ),
        .presetn    (presetn    ),
        .paddr      (paddr      ),
        .pwrite     (pwrite     ),
        .psel       (psel       ),
        .penable    (penable    ),
        .pwdata     (pwdata     ),
        .prdata     (prdata     ),
        .pready     (pready     ),
        .pslverr    (pslverr    ),

        .adc_clk    (adc_clk    ),
        .adc_clkn   (adc_clkn   ),
        .prstn      (prstn      ),

        .soc        (soc        ),
        .muxon      (muxon      ),
        .ch_sel     (ch_sel     ),
        .eoc        (eoc        ),
        .adc_data   (adc_data   ),

        .cal_st     (cal_st     ),
        .cal_done   (cal_done   ),
        .cal_val    (cal_val    ),

        .mctm_trig  (mctm_trig  ),

        .adc_int    (adc_int    ),
        .dma_ndreq      (dma_ndreq      ),
        .dma_ack        (dma_ack        ),
        .preempt_rst_n  (preempt_rst_n  )
    );

    //==========================================================================
    // Clock Generation
    //==========================================================================
    initial begin
        pclk = 0;
        forever #(PCLK_PERIOD / 2) pclk = ~pclk;
    end

    initial begin
        adc_clk = 0;
        forever #(ADCCLK_PERIOD / 2) adc_clk = ~adc_clk;
    end

    always @(adc_clk) begin
        adc_clkn = ~adc_clk;
    end

    //==========================================================================
    // Reset
    //==========================================================================
    initial begin
        presetn = 1'b0;
        prstn   = 1'b0;
        #200;
        presetn = 1'b1;
        prstn   = 1'b1;
        #200;
        main_test();
    end

    //==========================================================================
    // Timeout Protection
    //==========================================================================
    initial begin
        all_done = 1'b0;
        #500000;
        if (!all_done) begin
            $display("[TIMEOUT] Simulation timed out");
            $display("[FAIL] Timeout");
            $finish;
        end
    end

    //==========================================================================
    // Waveform Dump (FSDB for Verdi)
    //==========================================================================
    initial begin
    `ifdef VCS
        $fsdbDumpfile("sim/waveform.fsdb");
        $fsdbDumpvars(0, tb_adc_top_32ch);
    `else
        $dumpfile("sim/waveform.vcd");
        $dumpvars(0, tb_adc_top_32ch);
    `endif
    end

    //==========================================================================
    // Analog Model
    //==========================================================================
    // Detects SOC rising edge → counts SPT → samples voltage →
    // 14-bit SAR conversion → EOC on negedge adc_clk
    //==========================================================================
    adc_analog_model #(.CONV_BITS(TB_ADC_DATA_W), .CAL_CYCLES(20),
                        .ADC_NUM_CH(TB_ADC_NUM_CH), .ADC_DATA_W(TB_ADC_DATA_W))
    u_analog (
        .adc_clk        (adc_clk   ),
        .prstn          (prstn     ),
        .soc            (soc       ),
        .muxon          (muxon     ),
        .ch_sel         (ch_sel    ),
        .eoc            (eoc       ),
        .adc_data       (adc_data  ),
        .preempt_rst_n  (preempt_rst_n  ),  // from DUT
        .ovrd_en        (1'b0      ),  // unit TB: always self-timed
        .ovrd_force_eoc (1'b0      ),
        .ovrd_adc_data  ({TB_ADC_DATA_W{1'b0}}),
        .cal_st         (cal_st    ),
        .adc_en         (u_dut.cfg_adc_en ),  // ADC_EN (PCLK-domain, synced to ADC_CLK)
        .cal_done       (cal_done  ),
        .cal_val        (cal_val   )
    );
    // Calibration is modelled inside u_analog above (fixed 20-cycle auto
    // calibration, cal_done level held while cal_st high). No top-level
    // calibration model is needed here.
    //==========================================================================

    //==========================================================================
    // APB Master Tasks
    //==========================================================================
    task apb_write;
        input [15:0] addr;
        input [31:0] data;
        begin
            @(posedge pclk);
            paddr   = addr;
            pwdata  = data;
            pwrite  = 1'b1;
            psel    = 1'b1;
            penable = 1'b0;
            @(posedge pclk);
            penable = 1'b1;
            @(posedge pclk);
            psel    = 1'b0;
            penable = 1'b0;
        end
    endtask

    task apb_read;
        input  [15:0] addr;
        output [31:0] data;
        begin
            @(posedge pclk);
            paddr   = addr;
            pwrite  = 1'b0;
            psel    = 1'b1;
            penable = 1'b0;
            @(posedge pclk);
            penable = 1'b1;
            @(posedge pclk);
            data    = prdata;
            psel    = 1'b0;
            penable = 1'b0;
        end
    endtask

    //==========================================================================
    // Test 1: APB Register Write/Read (N=32 adapted)
    //==========================================================================
    task tc_reg_rw;
        begin
            $display("");
            $display("=== Test 1: APB Register RW (N=32) === @%0t", $time);

            // LP_SEQ_LEN reset value check (before any write): LP_SEQ_LEN_RST=32=0x20
            // W_LP_SEQ_LEN=6bit for N=32 (vs 4bit for N=8). This is the meaningful
            // N=32 adaptation of the APB RW sanity.
            apb_read(ADDR_LP_SEQ_LEN, got);
            if (got == 32'h0000_0020) begin
                $display("[PASS] LP_SEQ_LEN reset=0x20 (N=32, 6bit field) @%0t", $time);
                pass = pass + 1;
            end else begin
                $display("[FAIL] LP_SEQ_LEN reset expected 0x20, got 0x%08h", got);
                fail = fail + 1;
            end

            // CTRL: write without SW_RST and read back.
            // Write 0x0000_7FF9: ADC_EN=1(bit0), SW_RST=0(bit1), DATA_ALIGN=1(bit3),
            //   SPT0=7([10:8]), SPT1=7([13:11]), CONT_MODE=1(bit14), SMPL_INTERVAL=0
            //   ([22:16]=0x00). bits[7:4] written 0xF but RSVD RO → read 0; [15]/[23:16]
            //   above SMPL_INTERVAL also RSVD read 0. Round-trip readback = 0x0000_7F09
            //   (only RW fields reflect the write; RSVD bits read 0 per spec §3.2).
            //   NOTE: 8ch/26ch TBs assert 0x7FF9 (ignore RSVD read-0) → known pre-existing
            //   FAIL there (non-RTL bug, exit 0 via $finish); this 32ch TB asserts the
            //   correct round-trip 0x7F09.
            apb_write(ADDR_CTRL, 32'h0000_7FF9);
            apb_read(ADDR_CTRL, got);
            if (got == 32'h0000_7F09) begin
                $display("[PASS] CTRL write/read: wrote 0x7FF9, read 0x%0h (RSVD bits read 0)", got);
                pass = pass + 1;
            end else begin
                $display("[FAIL] CTRL expected 0x7F09, got 0x%0h", got);
                fail = fail + 1;
            end

            apb_write(ADDR_CTRL, 32'h0000_0000);

            // TRIG: write and read back
            apb_write(ADDR_TRIG, 32'h0000_7F7E);
            apb_read(ADDR_TRIG, got);
            if (got == 32'h0000_7E7E) begin
                $display("[PASS] TRIG write/read: 0x%0h", got);
                pass = pass + 1;
            end else begin
                $display("[FAIL] TRIG expected 0x7E7E, got 0x%0h", got);
                fail = fail + 1;
            end
            apb_write(ADDR_TRIG, 32'h0000_0000);

            // INT_EN: write and read
            apb_write(ADDR_INT_EN, 32'h0000_003F);
            apb_read(ADDR_INT_EN, got);
            if (got == 32'h0000_003F) begin
                $display("[PASS] INT_EN write/read: 0x%0h", got);
                pass = pass + 1;
            end else begin
                $display("[FAIL] INT_EN expected 0x3F, got 0x%0h", got);
                fail = fail + 1;
            end

            // ANA_CFG: 16-bit write/read (spec: [31:16] reserved RO zero)
            apb_write(ADDR_ANA_CFG, 32'hA5A5_A5A5);
            apb_read(ADDR_ANA_CFG, got);
            if (got == 32'h0000_A5A5) begin
                $display("[PASS] ANA_CFG write/read: 0x%0h", got);
                pass = pass + 1;
            end else begin
                $display("[FAIL] ANA_CFG expected 0x0000A5A5, got 0x%0h", got);
                fail = fail + 1;
            end

            // LP_SEQ0: write and read
            apb_write(ADDR_LP_SEQ0, 32'h03020100);
            apb_read(ADDR_LP_SEQ0, got);
            if (got == 32'h03020100) begin
                $display("[PASS] LP_SEQ0 write/read: 0x%0h", got);
                pass = pass + 1;
            end else begin
                $display("[FAIL] LP_SEQ0 expected 0x03020100, got 0x%0h", got);
                fail = fail + 1;
            end

            // DMA_CTRL: write and read
            apb_write(ADDR_DMA_CTRL, 32'h0000_003F);
            apb_read(ADDR_DMA_CTRL, got);
            if (got == 32'h0000_003F) begin
                $display("[PASS] DMA_CTRL write/read: 0x%0h", got);
                pass = pass + 1;
            end else begin
                $display("[FAIL] DMA_CTRL expected 0x3F, got 0x%0h", got);
                fail = fail + 1;
            end

            // LP_SEQ_LEN 6-bit RW (N=32 → W_LP_SEQ_LEN=6): write 0x15(21), read 0x15,
            // restore 0x20, read 0x20. Exercises the 6-bit width.
            apb_write(ADDR_LP_SEQ_LEN, 32'h0000_0015);
            apb_read(ADDR_LP_SEQ_LEN, got);
            if (got == 32'h0000_0015) begin
                $display("[PASS] LP_SEQ_LEN 6bit RW: write 0x15 read 0x15");
                pass = pass + 1;
            end else begin
                $display("[FAIL] LP_SEQ_LEN expected 0x15, got 0x%08h", got);
                fail = fail + 1;
            end
            apb_write(ADDR_LP_SEQ_LEN, 32'h0000_0020);
            apb_read(ADDR_LP_SEQ_LEN, got);
            if (got == 32'h0000_0020) begin
                $display("[PASS] LP_SEQ_LEN 6bit RW: restore 0x20 read 0x20");
                pass = pass + 1;
            end else begin
                $display("[FAIL] LP_SEQ_LEN expected 0x20, got 0x%08h", got);
                fail = fail + 1;
            end

            $display("--- Test 1 complete --- @%0t", $time);
        end
    endtask

    //==========================================================================
    // Test 2: 32-entry LP Sequence Sweep (CORE — closes b75842f gap)
    //==========================================================================
    // LP sequence: CH0→CH1→...→CH31 (32 entries, all 32 channels in order)
    // Programs LP_SEQ0..LP_SEQ7 (8 groups × 4 entries = 32), LP_SEQ_LEN=32,
    // SW-triggers, then reads back ALL LP_DATA[0:31] checking VALID + data.
    // CRITICAL: LP_DATA[26:31] @0x8C~0xA0 are the b75842f addresses (old
    // is_lp_data upper bound 0x088 excluded them → default → read 0).
    // With fix: is_lp_data covers 0x024..0x0A0, lp_data_idx<NUM_LP_DATA guard.
    //==========================================================================
    task tc_lp_seq_32_sweep;
        integer n;
        reg [31:0] ch_data;
        reg [31:0] stat;
        begin
            $display("");
            $display("=== Test 2: 32-entry LP Sequence Sweep (b75842f gap close) === @%0t", $time);

            // Start clean: software reset to clear all state
            apb_write(ADDR_CTRL, 32'h0000_0002);  // SW_RST=1
            #2000;
            apb_write(ADDR_TRIG, 32'h0000_0000);
            #100;

            // ─── Program LP_SEQ0..LP_SEQ7: CH0→CH31 in order ───
            // Each group encodes 4 consecutive channels in 4 byte slots (byte0=entry0).
            // W_CH_SEL=5bit for N=32 → each channel value ≤0x1F=31 fits.
            apb_write(ADDR_LP_SEQ0 +  0, 32'h03020100);  // CH0,1,2,3
            apb_write(ADDR_LP_SEQ0 +  4, 32'h07060504);  // CH4,5,6,7
            apb_write(ADDR_LP_SEQ0 +  8, 32'h0B0A0908);  // CH8,9,10,11
            apb_write(ADDR_LP_SEQ0 + 12, 32'h0F0E0D0C);  // CH12,13,14,15
            apb_write(ADDR_LP_SEQ0 + 16, 32'h13121110);  // CH16,17,18,19
            apb_write(ADDR_LP_SEQ0 + 20, 32'h17161514);  // CH20,21,22,23
            apb_write(ADDR_LP_SEQ0 + 24, 32'h1B1A1918);  // CH24,25,26,27
            apb_write(ADDR_LP_SEQ0 + 28, 32'h1F1E1D1C);  // CH28,29,30,31
            apb_write(ADDR_LP_SEQ_LEN, 32'h0000_0020);   // 32 entries
            $display("[LP_SEQ] 32 entries: CH0→CH31 (LP_SEQ0..LP_SEQ7) @%0t", $time);

            // Enable ADC: ADC_EN=1, SPT0=0 (3 cycles ~120ns sampling), SMPL_INTERVAL=0
            apb_write(ADDR_CTRL, 32'h0000_0001);
            #200;

            // Trigger LP sequence
            $display("[TRIG] LP 32-entry sweep START @%0t", $time);
            apb_write(ADDR_TRIG, 32'h0000_0002);  // LP_SW_TRG_EN only
            apb_write(ADDR_TRIG, 32'h0000_0003);  // LP_SW_TRIG + LP_SW_TRG_EN

            // Wait for all 32 samples to complete (~22us) + margin
            #50000;

            // ─── Check status: should be idle (LP_BUSY=0, HP_BUSY=0) ───
            apb_read(ADDR_STAT, stat);
            $display("[STAT] After 32-entry sweep: LP_BUSY=%d HP_BUSY=%d ADC_BUSY=%d @%0t",
                     stat[1], stat[2], stat[0], $time);

            // ─── Read back ALL 32 LP_DATA, explicit emphasis on [26:31] ───
            // Index alignment: seq_fsm EOC captures eoc_idx_r=lp_seq_ptr, lp_data_wr_en=1<<lp_seq_ptr.
            // Sequence CH0→CH31 → LP_DATA[n] written with adc_data captured when ch_sel=n
            // → exp_data[n]. Direct compare ch_data[13:0] === exp_data[n].
            $display("--- LP_DATA[0:31] Readback (right-aligned 14bit) ---");
            for (n = 0; n < 32; n = n + 1) begin
                apb_read(ADDR_LP_DATA0 + n*4, ch_data);
                // VALID check
                if (ch_data[31]) begin
                    pass = pass + 1;
                end else begin
                    $display("[FAIL] LP_DATA[%0d] @0x%04h VALID=0", n, ADDR_LP_DATA0 + n*4);
                    fail = fail + 1;
                end
                // Data match check (right-aligned 14bit in 16bit DATA field)
                if (ch_data[13:0] === exp_data[n]) begin
                    pass = pass + 1;
                end else begin
                    $display("[FAIL] LP_DATA[%0d] @0x%04h data mismatch: got 0x%04h exp 0x%04h",
                             n, ADDR_LP_DATA0 + n*4, ch_data[13:0], exp_data[n]);
                    fail = fail + 1;
                end
                // Explicit gap-closure banner for the b75842f addresses [26:31]
                if (n >= 26) begin
                    $display("[GAP-CLOSE b75842f] LP_DATA[%0d] @0x%04h = 0x%08h  VALID=%b  data=0x%04h  exp=0x%04h",
                             n, ADDR_LP_DATA0 + n*4, ch_data, ch_data[31], ch_data[13:0], exp_data[n]);
                end
            end

            $display("--- Test 2 complete --- @%0t", $time);
        end
    endtask

    //==========================================================================
    // Test 3: LP_DATA Boundary + LP_SEQ_RSV + LP_SEQ_LEN RW
    //==========================================================================
    // After Test 2's read-clear loop, lp_valid_pclk[n]=0 for all n but
    // lp_data[n] data field is preserved (read-clear only clears VALID).
    //==========================================================================
    task tc_lp_data_boundary;
        reg [31:0] got_b;
        begin
            $display("");
            $display("=== Test 3: LP_DATA Boundary + LP_SEQ_RSV + LP_SEQ_LEN RW === @%0t", $time);

            // ─── 0xA0 boundary (LP_DATA[31], last b75842f address) ───
            // VALID cleared by Test 2 read, but data field preserved.
            // If is_lp_data upper bound were <0xA0 (pre-b75842f bug), this read
            // would fall through to default → 0x00000000. With fix: returns
            // {1'b0, 15'h0, lp_data[31]} = {0, 15'h0, exp_data[31]}.
            apb_read(ADDR_LP_DATA0 + 31*4, got_b);  // 0xA0
            if (got_b[31] == 1'b0 && got_b[13:0] === exp_data[31]) begin
                $display("[PASS] 0xA0 = LP_DATA[31] (data=0x%04h preserved, VALID cleared) — is_lp_data upper bound = 0xA0",
                         got_b[13:0]);
                pass = pass + 1;
            end else begin
                $display("[FAIL] 0xA0 read = 0x%08h (exp VALID=0 data=0x%04h)", got_b, exp_data[31]);
                fail = fail + 1;
            end

            // ─── 0xA4 (HP_DATA0): NOT LP_DATA ───
            // No HP triggered → hp_data[0]=0, hp_valid_pclk[0]=0.
            // Sanity that is_lp_data upper bound is exactly 0xA0 (HP_DATA region intact,
            // no misclassify at boundary).
            apb_read(ADDR_HP_DATA0, got_b);  // 0xA4
            if (got_b == 32'h0000_0000) begin
                $display("[PASS] 0xA4 = HP_DATA0 reads 0 (no LP/HP misclassify at 0xA0/0xA4 boundary)");
                pass = pass + 1;
            end else begin
                $display("[FAIL] 0xA4 read = 0x%08h (exp 0)", got_b);
                fail = fail + 1;
            end

            // ─── LP_SEQ_LEN 6-bit RW (isolated, redundant with Test 1) ───
            apb_write(ADDR_LP_SEQ_LEN, 32'h0000_0015);  // 21
            apb_read(ADDR_LP_SEQ_LEN, got_b);
            if (got_b == 32'h0000_0015) begin
                $display("[PASS] LP_SEQ_LEN 6bit RW: 0x15");
                pass = pass + 1;
            end else begin
                $display("[FAIL] LP_SEQ_LEN expected 0x15, got 0x%08h", got_b);
                fail = fail + 1;
            end
            apb_write(ADDR_LP_SEQ_LEN, 32'h0000_0020);  // restore 32
            apb_read(ADDR_LP_SEQ_LEN, got_b);
            if (got_b == 32'h0000_0020) begin
                $display("[PASS] LP_SEQ_LEN 6bit RW: restore 0x20");
                pass = pass + 1;
            end else begin
                $display("[FAIL] LP_SEQ_LEN expected 0x20, got 0x%08h", got_b);
                fail = fail + 1;
            end

            // ─── LP_SEQ7 @0xD4 readback (last group, N=32 → 8 groups all implemented) ───
            apb_read(ADDR_LP_SEQ0 + 7*4, got_b);  // 0xD4
            if (got_b == 32'h1F1E1D1C) begin
                $display("[PASS] LP_SEQ7 @0xD4 = 0x%08h (CH28,29,30,31 — all 8 groups implemented at N=32)", got_b);
                pass = pass + 1;
            end else begin
                $display("[FAIL] LP_SEQ7 expected 0x1F1E1D1C, got 0x%08h", got_b);
                fail = fail + 1;
            end

            // ─── PARAM_SEQ_RSV: entry rsv high bits read back 0 ───
            // N=32 → W_CH_SEL=5bit, each 8-bit LP_SEQ slot has 5 valid + 3 rsv bits.
            // Write 0xFFFFFFFF → each byte 0xFF → low 5bit 0x1F stored, rsv high 3bit 0
            // → readback 0x1F1F1F1F.
            apb_write(ADDR_LP_SEQ0, 32'hFFFFFFFF);
            apb_read(ADDR_LP_SEQ0, got_b);
            if (got_b == 32'h1F1F1F1F) begin
                $display("[PASS] PARAM_SEQ_RSV: LP_SEQ0 rsv high bits read 0 (0x%08h)", got_b);
                pass = pass + 1;
            end else begin
                $display("[FAIL] PARAM_SEQ_RSV: expected 0x1F1F1F1F, got 0x%08h", got_b);
                fail = fail + 1;
            end
            apb_write(ADDR_LP_SEQ0, 32'h03020100);  // restore

            $display("--- Test 3 complete --- @%0t", $time);
        end
    endtask


    //==========================================================================
    // Main Test Flow
    //==========================================================================
    task main_test;
        begin
            pass = 0;
            fail = 0;

            tc_reg_rw;
            tc_lp_seq_32_sweep;
            tc_lp_data_boundary;

            $display("");
            $display("========================================");
            $display("  tb_adc_top_32ch Simulation Complete");
            $display("  Passed: %0d   Failed: %0d", pass, fail);
            $display("========================================");
            if (fail > 0) begin
                $display("[FAIL] Some tests failed!");
            end else begin
                $display("[PASS] All tests passed!");
            end
            all_done = 1'b1;
            $finish;
        end
    endtask

endmodule
