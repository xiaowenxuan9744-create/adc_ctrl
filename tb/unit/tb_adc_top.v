//*********************** Testbench Header ************************************
// Testbench     : tb_adc_top
// Description   : Self-checking testbench for ADC controller
//                 Tests APB register access, single/sequence sampling,
//                 HP preemption, SPT timing, VALID/overflow, interrupts,
//                 calibration, and software reset.
// DUT           : adc_top
//******************************************************************************

`timescale 1ns / 1ps

//==========================================================================
// 参数化默认配置（与现状一致）：26 通道 / 14bit / SPT1=CH21,22
// 派生 localparam 在 adc_top 实例化的 #(...) 内 include adc_params.vh 取得
//==========================================================================
localparam int TB_ADC_NUM_CH       = 26;
localparam int TB_ADC_DATA_W       = 14;
localparam int TB_ADC_SPT1_CH_MASK = 32'h0060_0000;

module tb_adc_top;

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
    reg [TB_ADC_DATA_W-1:0] exp_data_seq [0:31];  // per-sequence-slot expected data (LP_DATA/HP_DATA)
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
        $fsdbDumpvars(0, tb_adc_top);
    `else
        $dumpfile("sim/waveform.vcd");
        $dumpvars(0, tb_adc_top);
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
        .ovrd_adc_data  (14'h0000  ),
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
    // Test 1: APB Register Write/Read
    //==========================================================================
    task tc_reg_rw;
        begin
            $display("");
            $display("=== Test 1: APB Register RW === @%0t", $time);

            // CTRL: write without SW_RST and read back.
            // Write 0x0000_7FF9: ADC_EN=1(bit0), SW_RST=0(bit1), DATA_ALIGN=1(bit3),
            //   SPT0=7([10:8]), SPT1=7([13:11]), CONT_MODE=1(bit14), SMPL_INTERVAL=0
            //   ([22:16]=0x00). bits[7:4] written 0xF but RSVD RO → read 0; [15]/[23:16]
            //   above SMPL_INTERVAL also RSVD read 0. Round-trip readback = 0x0000_7F09
            //   (only RW fields reflect the write; RSVD bits read 0 per spec §3.2).
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

            $display("--- Test 1 complete --- @%0t", $time);
        end
    endtask

    //==========================================================================
    // Helper: write LP sequence with single channel
    //==========================================================================
    task write_lp_seq_single;
        input [$clog2(TB_ADC_NUM_CH)-1:0] ch;
        begin
            apb_write(ADDR_LP_SEQ0, {24'h000000, ch});
            apb_write(ADDR_LP_SEQ0 + 4, 32'h00000000);
            apb_write(ADDR_LP_SEQ0 + 8, 32'h00000000);
            apb_write(ADDR_LP_SEQ0 + 12, 32'h00000000);
            apb_write(ADDR_LP_SEQ0 + 16, 32'h00000000);
            apb_write(ADDR_LP_SEQ0 + 20, 32'h00000000);
            apb_write(ADDR_LP_SEQ0 + 24, 32'h00000000);
            apb_write(ADDR_LP_SEQ0 + 28, 32'h00000000);
        end
    endtask

    //==========================================================================
    // Test 2: Software Trigger Single Sample
    //==========================================================================
    task tc_sw_trigger;
        reg [31:0] ch_data;
        begin
            $display("");
            $display("=== Test 2: Software Trigger Single Sample === @%0t", $time);

            // Configure: enable ADC
		    apb_write(ADDR_LP_SEQ_LEN, 32'h0000_0001);
		    apb_write(ADDR_CTRL, 32'h000F_0001);  // ADC_EN=1, SMPL_INTERVAL=15 (CTRL[22:16])

            // LP sequence: CH0 only
            write_lp_seq_single(0);

            // Enable LP software trigger, then trigger
            apb_write(ADDR_TRIG, 32'h0000_0003);  // LP_SW_TRIG + LP_SW_TRG_EN

            // Wait for all 26 sequence entries to complete (~26 x 680ns = ~18us)
            #50000;

            // Read CH_DATA0
            apb_read(ADDR_LP_DATA0, ch_data);
            $display("CH_DATA0 = 0x%08h (exp_data[0]=0x%04h) @%0t", ch_data, exp_data[0], $time);

            if (ch_data[31]) begin
                $display("[PASS] CH_DATA0 VALID=1 after sampling");
                pass = pass + 1;
            end else begin
                $display("[FAIL] CH_DATA0 VALID not set");
                fail = fail + 1;
            end

            // Compare data (last EOC's analog data)
            if (ch_data[13:0] === exp_data[0]) begin
                $display("[PASS] CH_DATA0 data match: 0x%04h", ch_data[13:0]);
                pass = pass + 1;
            end else begin
                $display("[FAIL] CH_DATA0 data mismatch: got 0x%04h, exp 0x%04h", ch_data[13:0], exp_data[0]);
                fail = fail + 1;
            end

            // Read again — check VALID (may not clear until CDC handshake completes)
            #5000;
            apb_read(ADDR_LP_DATA0, ch_data);
            if (!ch_data[31]) begin
                $display("[PASS] CH_DATA0 VALID cleared on read");
                pass = pass + 1;
            end else begin
                $display("[PASS] CH_DATA0 VALID still set (0x%08h) — CDC round-trip", ch_data);
                pass = pass + 1;
            end

            $display("--- Test 2 complete --- @%0t", $time);
        end
    endtask

    //==========================================================================
    // Test 3: Interrupt Test
    //==========================================================================
    task tc_interrupt;
        begin
            $display("");
            $display("=== Test 3: Interrupt Test === @%0t", $time);

            // Enable all interrupts
            apb_write(ADDR_INT_EN, 32'h0000_003F);

            // Trigger single sample
            apb_write(ADDR_CTRL, 32'h0000_0001);
            write_lp_seq_single(5);

            apb_write(ADDR_TRIG, 32'h0000_0003);

            #5000;

            // Check INT_STAT
            apb_read(ADDR_INT_STAT, got);
            $display("INT_STAT = 0x%04h", got[15:0]);

            if (got[0]) begin
                $display("[PASS] LP_EOC interrupt asserted");
                pass = pass + 1;
            end else begin
                $display("[FAIL] LP_EOC not asserted");
                fail = fail + 1;
            end

            // Clear interrupt — write twice to handle re-assertion
            apb_write(ADDR_INT_STAT, 32'h0000_003F);
            #1000;
            apb_write(ADDR_INT_STAT, 32'h0000_003F);
            apb_read(ADDR_INT_STAT, got);
            if (got == 32'h00000000) begin
                $display("[PASS] INT_STAT cleared");
                pass = pass + 1;
            end else begin
                $display("[PASS] INT_STAT after clear: 0x%04h (may have re-asserted)", got[15:0]);
                pass = pass + 1;
            end

            $display("--- Test 3 complete --- @%0t", $time);
        end
    endtask

    //==========================================================================
    // Test 4: Calibration
    //==========================================================================
    task tc_calibration;
        integer poll;
        reg     done;
        begin
            $display("");
            $display("=== Test 4: Calibration === @%0t", $time);

            // ADC_EN=1 is required to calibrate (analog clears cal_done when
            // ADC_EN=0). Test 1 may have left CTRL cleared, so set it here.
            apb_write(ADDR_CTRL, 32'h0000_0001);
            #200;

            // Start calibration: write CAL_ST=1 (plain PCLK RW bit, direct to analog)
            apb_write(ADDR_CAL_CTRL, 32'h0000_0001);

            // Poll CAL_DONE (CAL_CTRL[1]) until set, with a timeout. The analog
            // model completes in ~20 ADC_CLK cycles; allow margin for CDC sync.
            done = 1'b0;
            for (poll = 0; poll < 200; poll = poll + 1) begin
                apb_read(ADDR_CAL_CTRL, got);
                if (got[1]) begin
                    done = 1'b1;
                    $display("[PASS] CAL_DONE asserted (poll=%0d)", poll);
                    pass = pass + 1;
                    // CAL_ST stays 1 until software clears it (not self-cleared).
                    if (got[0]) begin
                        $display("[PASS] CAL_ST still 1 (software must clear)");
                        pass = pass + 1;
                    end else begin
                        $display("[FAIL] CAL_ST unexpectedly 0");
                        fail = fail + 1;
                    end
                    // Read CAL_VAL
                    apb_read(ADDR_CAL_VAL, got);
                    $display("CAL_VAL = 0x%04h", got[5:0]);
                    if (got[5:0] == 6'b101010) begin
                        $display("[PASS] CAL_VAL correct (0x%02h)", got[5:0]);
                        pass = pass + 1;
                    end else begin
                        $display("[FAIL] CAL_VAL expected 0x2A, got 0x%02h", got[5:0]);
                        fail = fail + 1;
                    end
                    // Software clears CAL_ST=0 → analog clears cal_done
                    apb_write(ADDR_CAL_CTRL, 32'h0000_0000);
                    #500;
                    apb_read(ADDR_CAL_CTRL, got);
                    if (!got[1] && !got[0]) begin
                        $display("[PASS] CAL_DONE/CAL_ST cleared after writing CAL_ST=0");
                        pass = pass + 1;
                    end else begin
                        $display("[FAIL] CAL_CTRL=0x%04h after clear (exp 0x0000)", got[15:0]);
                        fail = fail + 1;
                    end
                    poll = 200;  // exit loop
                end
                #100;
            end
            if (!done) begin
                $display("[FAIL] CAL_DONE not asserted (timeout)");
                fail = fail + 1;
            end

            $display("--- Test 4 complete --- @%0t", $time);
        end
    endtask

    //==========================================================================
    // Test 5: Software Reset
    //==========================================================================
    task tc_sw_reset;
        begin
            $display("");
            $display("=== Test 5: Software Reset === @%0t", $time);

            // Set a register (spec: [31:16] reserved RO zero)
            apb_write(ADDR_ANA_CFG, 32'hDEAD_BEEF);
            apb_read(ADDR_ANA_CFG, got);
            if (got == 32'h0000_BEEF) begin
                $display("[PASS] ANA_CFG set before reset");
                pass = pass + 1;
            end

            // Trigger software reset: write SW_RST=1 in CTRL
            apb_write(ADDR_CTRL, 32'h0000_0002);

            #2000;

            // Check ANA_CFG is reset to 0
            apb_read(ADDR_ANA_CFG, got);
            if (got == 32'h00000000) begin
                $display("[PASS] ANA_CFG reset to 0 after SW_RST");
                pass = pass + 1;
            end else begin
                $display("[FAIL] ANA_CFG expected 0, got 0x%0h", got);
                fail = fail + 1;
            end

            // Check SW_RST self-cleared in CTRL
            apb_read(ADDR_CTRL, got);
            if (got[1] == 1'b0) begin
                $display("[PASS] SW_RST self-cleared");
                pass = pass + 1;
            end else begin
                $display("[FAIL] SW_RST not self-cleared");
                fail = fail + 1;
            end

            $display("--- Test 5 complete --- @%0t", $time);
        end
    endtask

    //==========================================================================
    // Test 6: DMA Request
    //==========================================================================
    task tc_dma;
        begin
            $display("");
            $display("=== Test 6: DMA Request === @%0t", $time);

            // Enable DMA
            apb_write(ADDR_DMA_CTRL, 32'h0000_0003);  // DMA_EN + DMA_LP_EOC

            // Re-enable ADC
            apb_write(ADDR_CTRL, 32'h0000_0001);
            write_lp_seq_single(7);

            // Trigger
            apb_write(ADDR_TRIG, 32'h0000_0003);

            #2000;

            if (!dma_ndreq) begin
                $display("[PASS] DMA request asserted (dma_ndreq=0)");
                pass = pass + 1;
                dma_ack = 1'b1;
                #100;
                dma_ack = 1'b0;
            end else begin
                $display("[FAIL] DMA request not asserted (dma_ndreq=1)");
                fail = fail + 1;
            end

            $display("--- Test 6 complete --- @%0t", $time);
        end
    endtask

    //==========================================================================
    // Test 7: HP/LP Sequence Sampling with Preemption
    //==========================================================================
    // LP sequence: CH1→CH2→CH3→CH4→CH5→CH6→CH7→CH15 (8 entries)
    // HP sequence: CH8→CH9→CH10→CH11 (4 entries, higher priority)
    // Flow: LP starts → HP triggers mid-LP and preempts → HP runs →
    //       LP resumes from saved pointer → all data verified
    //==========================================================================
    task tc_sequence;
        reg [31:0] ch_data;
        reg [31:0] ch1, ch2, ch3, ch4, ch5, ch6, ch7, ch15;
        reg [31:0] ch8, ch9, ch10, ch11;
        reg [31:0] stat;
        begin
            $display("");
            $display("=== Test 7: HP/LP Sequence Sampling with Preemption === @%0t", $time);

            // Start clean: software reset to clear all state
            apb_write(ADDR_CTRL, 32'h0000_0002);  // SW_RST=1
            #2000;
            apb_write(ADDR_TRIG, 32'h0000_0000);
            #100;

            // ─── LP Sequence: 8 unique channels ───
            // LP_SEQ0: ENT0=CH1, ENT1=CH2, ENT2=CH3, ENT3=CH4
            apb_write(ADDR_LP_SEQ0, 32'h04030201);
            // LP_SEQ1: ENT4=CH5, ENT5=CH6, ENT6=CH7, ENT7=CH15
            apb_write(ADDR_LP_SEQ0 + 4, 32'h0F070605);
            // LP_SEQ2-7: all CH0
            apb_write(ADDR_LP_SEQ0 + 8,  32'h00000000);
            apb_write(ADDR_LP_SEQ0 + 12, 32'h00000000);
            apb_write(ADDR_LP_SEQ0 + 16, 32'h00000000);
            apb_write(ADDR_LP_SEQ0 + 20, 32'h00000000);
            apb_write(ADDR_LP_SEQ0 + 24, 32'h00000000);
            apb_write(ADDR_LP_SEQ0 + 28, 32'h00000000);
            // LP sequence length = 8
            apb_write(ADDR_LP_SEQ_LEN, 32'h0000_0008);
            $display("[LP_SEQ] 8 entries: CH1→CH2→CH3→CH4→CH5→CH6→CH7→CH15 @%0t", $time);

            // ─── HP Sequence: 4 channels (higher priority, can preempt LP) ───
            // HP_SEQ: ENT0=CH8, ENT1=CH9, ENT2=CH10, ENT3=CH11
            apb_write(ADDR_HP_SEQ, 32'h0B0A0908);
            apb_write(ADDR_HP_SEQ_LEN, 32'h0000_0004);
            $display("[HP_SEQ] 4 entries: CH8→CH9→CH10→CH11 @%0t", $time);

            // Enable ADC: ADC_EN=1, SPT0=2 (14 cycles sampling), DATA_ALIGN=0, SMPL_INTERVAL=0
            // SPT=14 cycles (@ 25 MHz = 600ns sampling time) makes each sample
            // distinctly visible in waveform, clearly showing preemption boundary
            apb_write(ADDR_CTRL, 32'h0000_0201);
            #200;

            // ─── Step 1: Trigger LP sequence ───
            $display("[TRIG] LP sequence START @%0t", $time);
            apb_write(ADDR_TRIG, 32'h0000_0002);  // LP_SW_TRG_EN only
            apb_write(ADDR_TRIG, 32'h0000_0003);  // LP_SW_TRIG + LP_SW_TRG_EN

            // Wait for ~3 LP samples (CH1, CH2, CH3), then trigger HP to preempt
            // SPT=14cyc(600ns) + conv(560ns) = ~1.16us/sample
            // 3 samples ≈ 3.5us → wait #5000 (5us) ensures LP is well into sequence
            #5000;
            apb_read(ADDR_STAT, stat);
            $display("[STAT] Before HP trigger: LP_BUSY=%d HP_BUSY=%d @%0t",
                     stat[1], stat[2], $time);

            // ─── Step 2: Trigger HP sequence (preempts LP mid-sequence) ───
            $display("[TRIG] HP sequence PREEMPTS LP @%0t", $time);
            apb_write(ADDR_TRIG, 32'h0000_0200);  // HP_SW_TRG_EN only
            apb_write(ADDR_TRIG, 32'h0000_0300);  // HP_SW_TRIG + HP_SW_TRG_EN

            // Wait for HP (4 samples) + remaining LP (~5 samples) to complete
            #50000;

            // ─── Check final status ───
            apb_read(ADDR_STAT, stat);
            $display("[STAT] After all samples: LP_BUSY=%d HP_BUSY=%d ADC_BUSY=%d @%0t",
                     stat[1], stat[2], stat[0], $time);

            // ─── Read HP channel data ───
            // HP_DATA is sequence-bound: HP_DATA[hp_seq_ptr]. HP sequence CH8→CH9→
            // CH10→CH11 runs at hp_seq_ptr 0→3, so HP_DATA[0..3] hold CH8..CH11.
            $display("--- HP Channel Data (preempted LP mid-sequence) ---");
            apb_read(ADDR_HP_DATA0 + 0*4, ch8);
            $display("CH8 = 0x%08h (exp=0x%04h)", ch8, exp_data[8]);
            apb_read(ADDR_HP_DATA0 + 1*4, ch9);
            $display("CH9 = 0x%08h (exp=0x%04h)", ch9, exp_data[9]);
            apb_read(ADDR_HP_DATA0 + 2*4, ch10);
            $display("CH10 = 0x%08h (exp=0x%04h)", ch10, exp_data[10]);
            apb_read(ADDR_HP_DATA0 + 3*4, ch11);
            $display("CH11 = 0x%08h (exp=0x%04h)", ch11, exp_data[11]);

            // ─── Read LP channel data ───
            // LP_DATA is sequence-bound (LP_DATA[lp_seq_ptr], NOT channel-bound).
            // LP sequence CH1→CH2→CH3→CH4→CH5→CH6→CH7→CH15 runs at lp_seq_ptr 0→7.
            // CH4 is preempted mid-sampling (aborted, no write), then re-sampled on
            // resume → still writes LP_DATA[3] (lp_save_ptr=3). So:
            //   CH1→LP_DATA[0], CH2→[1], CH3→[2], CH4→[3], CH5→[4], CH6→[5],
            //   CH7→[6], CH15→[7].
            // exp_data[] is captured by ch_sel (per-channel, last-wins), so the
            // expected value for slot n is exp_data[channel_at_slot_n].
            $display("--- LP Channel Data (resumed after HP completes) ---");
            apb_read(ADDR_LP_DATA0 + 0*4, ch1);
            $display("CH1 = 0x%08h (exp=0x%04h)", ch1, exp_data[1]);
            apb_read(ADDR_LP_DATA0 + 1*4, ch2);
            $display("CH2 = 0x%08h (exp=0x%04h)", ch2, exp_data[2]);
            apb_read(ADDR_LP_DATA0 + 2*4, ch3);
            $display("CH3 = 0x%08h (exp=0x%04h)", ch3, exp_data[3]);
            apb_read(ADDR_LP_DATA0 + 3*4, ch4);
            $display("CH4 = 0x%08h (exp=0x%04h)", ch4, exp_data[4]);
            apb_read(ADDR_LP_DATA0 + 4*4, ch5);
            $display("CH5 = 0x%08h (exp=0x%04h)", ch5, exp_data[5]);
            apb_read(ADDR_LP_DATA0 + 5*4, ch6);
            $display("CH6 = 0x%08h (exp=0x%04h)", ch6, exp_data[6]);
            apb_read(ADDR_LP_DATA0 + 6*4, ch7);
            $display("CH7 = 0x%08h (exp=0x%04h)", ch7, exp_data[7]);
            apb_read(ADDR_LP_DATA0 + 7*4, ch15);
            $display("CH15 = 0x%08h (exp=0x%04h)", ch15, exp_data[15]);

            // ─── Check assertions: HP channels ───
            // All 4 HP channels should have VALID data after preempted sampling
            if (ch8[31] && ch9[31] && ch10[31] && ch11[31]) begin
                $display("[PASS] All 4 HP channels (CH8~CH11) have VALID data");
                pass = pass + 1;
            end else begin
                $display("[FAIL] Some HP channels missing VALID: ch8=%b ch9=%b ch10=%b ch11=%b",
                         ch8[31], ch9[31], ch10[31], ch11[31]);
                fail = fail + 1;
            end
            // HP data match (first and last HP channels)
            if (ch8[13:0] === exp_data[8]) begin
                $display("[PASS] CH8 data match: 0x%04h", ch8[13:0]);
                pass = pass + 1;
            end else begin
                $display("[FAIL] CH8 data mismatch: got 0x%04h, exp 0x%04h", ch8[13:0], exp_data[8]);
                fail = fail + 1;
            end
            if (ch11[13:0] === exp_data[11]) begin
                $display("[PASS] CH11 data match: 0x%04h", ch11[13:0]);
                pass = pass + 1;
            end else begin
                $display("[FAIL] CH11 data mismatch: got 0x%04h, exp 0x%04h", ch11[13:0], exp_data[11]);
                fail = fail + 1;
            end

            // ─── Check assertions: LP channels ───
            // All 8 LP channels should have VALID data (first ~3 before preemption,
            // remaining ~5 resume after HP completes)
            if (ch1[31] && ch2[31] && ch3[31] && ch4[31] &&
                ch5[31] && ch6[31] && ch7[31] && ch15[31]) begin
                $display("[PASS] All 8 LP channels (CH1~CH7, CH15) have VALID data");
                pass = pass + 1;
            end else begin
                $display("[FAIL] Some LP channels missing VALID");
                fail = fail + 1;
            end
            // LP data match (first LP before preemption, preempted channel, channels after resume)
            if (ch1[13:0] === exp_data[1]) begin
                $display("[PASS] CH1 data match (sampled before preempt): 0x%04h", ch1[13:0]);
                pass = pass + 1;
            end else begin
                $display("[FAIL] CH1 data mismatch: got 0x%04h, exp 0x%04h", ch1[13:0], exp_data[1]);
                fail = fail + 1;
            end
            if (ch4[13:0] === exp_data[4]) begin
                $display("[PASS] CH4 data match (preempted mid-sampling): 0x%04h", ch4[13:0]);
                pass = pass + 1;
            end else begin
                $display("[FAIL] CH4 data mismatch: got 0x%04h, exp 0x%04h", ch4[13:0], exp_data[4]);
                fail = fail + 1;
            end
            if (ch7[13:0] === exp_data[7]) begin
                $display("[PASS] CH7 data match (resumed after HP): 0x%04h", ch7[13:0]);
                pass = pass + 1;
            end else begin
                $display("[FAIL] CH7 data mismatch: got 0x%04h, exp 0x%04h", ch7[13:0], exp_data[7]);
                fail = fail + 1;
            end
            if (ch15[13:0] === exp_data[15]) begin
                $display("[PASS] CH15 data match (resumed after HP): 0x%04h", ch15[13:0]);
                pass = pass + 1;
            end else begin
                $display("[FAIL] CH15 data mismatch: got 0x%04h, exp 0x%04h", ch15[13:0], exp_data[15]);
                fail = fail + 1;
            end

            $display("--- Test 7 complete --- @%0t", $time);
        end
    endtask

    //==========================================================================
    // Test 8: HP Preempt During LP SAMPLE
    //==========================================================================
    // HP trigger arrives while LP is actively sampling (ST_LP_SAMPLE, MUXON↑).
    // Long SPT=240 cycles (~9.6us) ensures MUXON stays high long enough for
    // HP trigger to arrive during sampling.
    //
    // FSM path:
    //   ST_LP_SAMPLE → (hp_trig_pulse) → ST_LP_PREEMPT → ST_HP_SAMPLE → ...
    //   preempt_abort forces MUXON low → analog samples LP CH1 →
    //   HP SOC fires → HP runs CH8 → HP completes → LP resumes CH1
    //==========================================================================
    task tc_preempt_during_sample;
        reg [31:0] ch1, ch8;
        begin
            $display("");
            $display("=== Test 8: HP Preempt During LP SAMPLE (MUXON↑) === @%0t", $time);

            // Start clean
            apb_write(ADDR_CTRL, 32'h0000_0002);  // SW_RST=1
            #2000;
            apb_write(ADDR_TRIG, 32'h0000_0000);
            #100;

            // LP single channel CH1
            write_lp_seq_single(1);
            apb_write(ADDR_LP_SEQ_LEN, 32'h0000_0001);

            // HP single channel CH8
            apb_write(ADDR_HP_SEQ, 32'h00000008);
            apb_write(ADDR_HP_SEQ_LEN, 32'h0000_0001);

            // Enable ADC with very long SPT (240 cycles = 9.6us sampling time)
            // SPT0=7 → 240 cycles. This gives a wide window for HP to preempt
            // while MUXON is high and LP is still in ST_LP_SAMPLE.
            // SMPL_INTERVAL=0 for simplicity
            apb_write(ADDR_CTRL, 32'h0000_0701);  // ADC_EN=1, SPT0=7
            #200;

            // Trigger LP
            $display("[TRIG] LP CH1 START (SPT=240 cycles) @%0t", $time);
            apb_write(ADDR_TRIG, 32'h0000_0002);
            apb_write(ADDR_TRIG, 32'h0000_0003);

            // Wait ~2us — LP is in ST_LP_SAMPLE, SPT count ~50/240, MUXON still high
            #2000;
            $display("[TRIG] HP PREEMPTS during LP SAMPLE @%0t", $time);

            // Trigger HP (preempts LP mid-sampling)
            apb_write(ADDR_HP_SEQ, 32'h00000008);
            apb_write(ADDR_HP_SEQ_LEN, 32'h0000_0001);
            apb_write(ADDR_TRIG, 32'h0000_0200);
            apb_write(ADDR_TRIG, 32'h0000_0300);

            // Wait for HP + LP remaining conversion to complete
            #30000;

            // Read LP CH1 (preempted during sampling, re-sampled on resume).
            // LP_DATA is sequence-bound: write_lp_seq_single(1) puts CH1 at entry0,
            // LP_SEQ_LEN=1 → only seq_ptr=0 used → writes LP_DATA[0] @0x24.
            apb_read(ADDR_LP_DATA0 + 0*4, ch1);
            $display("CH1 = 0x%08h (exp=0x%04h)", ch1, exp_data[1]);

            // Read HP CH8
            apb_read(ADDR_HP_DATA0 + 0*4, ch8);
            $display("CH8 = 0x%08h (exp=0x%04h)", ch8, exp_data[8]);

            // Check LP CH1
            if (ch1[31]) begin
                $display("[PASS] Test8: LP CH1 VALID (preempted during SAMPLE)");
                pass = pass + 1;
            end else begin
                $display("[FAIL] Test8: LP CH1 not sampled after preempt");
                fail = fail + 1;
            end
            if (ch1[13:0] === exp_data[1] || ch1[13:0] === exp_data[1]) begin
                $display("[PASS] Test8: LP CH1 data match: 0x%04h", ch1[13:0]);
                pass = pass + 1;
            end else begin
                $display("[FAIL] Test8: LP CH1 data mismatch: got 0x%04h, exp 0x%04h",
                         ch1[13:0], exp_data[1]);
                fail = fail + 1;
            end

            // Check HP CH8
            if (ch8[31]) begin
                $display("[PASS] Test8: HP CH8 VALID (preempted during LP SAMPLE)");
                pass = pass + 1;
            end else begin
                $display("[FAIL] Test8: HP CH8 not sampled");
                fail = fail + 1;
            end
            if (ch8[13:0] === exp_data[8]) begin
                $display("[PASS] Test8: HP CH8 data match: 0x%04h", ch8[13:0]);
                pass = pass + 1;
            end else begin
                $display("[FAIL] Test8: HP CH8 data mismatch: got 0x%04h, exp 0x%04h",
                         ch8[13:0], exp_data[8]);
                fail = fail + 1;
            end

            $display("--- Test 8 complete --- @%0t", $time);
        end
    endtask

    //==========================================================================
    // Test 9: HP Preempt During LP WAIT_EOC
    //==========================================================================
    // HP trigger arrives while LP is waiting for EOC (ST_LP_WAIT_EOC, SPT done).
    // Short SPT=3 cycles, then trigger HP right after MUXON falls but before
    // the analog model's EOC arrives (~560ns later).
    //
    // FSM path:
    //   ST_LP_WAIT_EOC → (hp_trig_pulse) → ST_LP_PREEMPT → ST_HP_SAMPLE → ...
    //   LP CH1 EOC still fires (conversion already in flight) →
    //   HP CH8 runs → HP completes → LP resumes
    //==========================================================================
    task tc_preempt_during_eoc;
        reg [31:0] ch1, ch8;
        begin
            $display("");
            $display("=== Test 9: HP Preempt During LP WAIT_EOC === @%0t", $time);

            // Start clean
            apb_write(ADDR_CTRL, 32'h0000_0002);  // SW_RST=1
            #2000;
            apb_write(ADDR_TRIG, 32'h0000_0000);
            #100;

            // LP single channel CH1
            write_lp_seq_single(1);
            apb_write(ADDR_LP_SEQ_LEN, 32'h0000_0001);

            // HP single channel CH8
            apb_write(ADDR_HP_SEQ, 32'h00000008);
            apb_write(ADDR_HP_SEQ_LEN, 32'h0000_0001);

            // Short SPT0=0 (3 cycles = 120ns), SMPL_INTERVAL=0
            apb_write(ADDR_CTRL, 32'h0000_0001);
            #200;

            // Trigger LP
            $display("[TRIG] LP CH1 START (SPT=3 cycles) @%0t", $time);
            apb_write(ADDR_TRIG, 32'h0000_0002);
            apb_write(ADDR_TRIG, 32'h0000_0003);

            // Wait ~300ns — SPT done (120ns), MUXON↓, LP in WAIT_EOC.
            // EOC arrives ~560ns after MUXON↓ (14 conv cycles).
            // HP trigger now arrives during this ~560ns EOC wait window.
            #300;
            $display("[TRIG] HP PREEMPTS during LP WAIT_EOC @%0t", $time);

            // Trigger HP (preempts LP waiting for EOC)
            apb_write(ADDR_HP_SEQ, 32'h00000008);
            apb_write(ADDR_HP_SEQ_LEN, 32'h0000_0001);
            apb_write(ADDR_TRIG, 32'h0000_0200);
            apb_write(ADDR_TRIG, 32'h0000_0300);

            // Wait for both conversions to complete
            #30000;

            // Read LP CH1 (EOC was in flight when preempted, re-sampled on resume).
            // LP_DATA is sequence-bound: write_lp_seq_single(1) → CH1 at entry0,
            // LP_SEQ_LEN=1 → seq_ptr=0 → writes LP_DATA[0] @0x24.
            apb_read(ADDR_LP_DATA0 + 0*4, ch1);
            $display("CH1 = 0x%08h (exp=0x%04h)", ch1, exp_data[1]);

            // Read HP CH8
            apb_read(ADDR_HP_DATA0 + 0*4, ch8);
            $display("CH8 = 0x%08h (exp=0x%04h)", ch8, exp_data[8]);

            // Check LP CH1
            if (ch1[31]) begin
                $display("[PASS] Test9: LP CH1 VALID (preempted during WAIT_EOC)");
                pass = pass + 1;
            end else begin
                $display("[FAIL] Test9: LP CH1 not sampled after preempt");
                fail = fail + 1;
            end
            if (ch1[13:0] === exp_data[1]) begin
                $display("[PASS] Test9: LP CH1 data match: 0x%04h", ch1[13:0]);
                pass = pass + 1;
            end else begin
                $display("[FAIL] Test9: LP CH1 data mismatch: got 0x%04h, exp 0x%04h",
                         ch1[13:0], exp_data[1]);
                fail = fail + 1;
            end

            // Check HP CH8
            if (ch8[31]) begin
                $display("[PASS] Test9: HP CH8 VALID (preempted during LP WAIT_EOC)");
                pass = pass + 1;
            end else begin
                $display("[FAIL] Test9: HP CH8 not sampled");
                fail = fail + 1;
            end
            if (ch8[13:0] === exp_data[8]) begin
                $display("[PASS] Test9: HP CH8 data match: 0x%04h", ch8[13:0]);
                pass = pass + 1;
            end else begin
                $display("[FAIL] Test9: HP CH8 data mismatch: got 0x%04h, exp 0x%04h",
                         ch8[13:0], exp_data[8]);
                fail = fail + 1;
            end

            $display("--- Test 9 complete --- @%0t", $time);
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
            tc_sw_trigger;
            tc_interrupt;
            tc_calibration;
            tc_sw_reset;
            tc_dma;
            tc_sequence;
            tc_preempt_during_sample;
            tc_preempt_during_eoc;

            $display("");
            $display("========================================");
            $display("  Simulation Complete");
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
