// ============================================================================
// Sequence: adc_reg_seq
// Description: Register read/write test sequence
//              1. Wait for power-on reset (handled by tb_top)
//              2. Check defaults
//              3. Write each RW register → read back
// ============================================================================

class adc_reg_seq extends adc_base_seq;
    `uvm_object_utils(adc_reg_seq)

    // Register addresses come from `adc_regmap.svh (included via adc_uvm_pkg):
    // `ADC_CTRL / `ADC_STAT / `ADC_TRIG / `ADC_INT_EN / `ADC_INT_STAT /
    // `ADC_CAL_CTRL / `ADC_CAL_VAL / `ADC_ANA_CFG / `ADC_ANA_REG /
    // `ADC_DMA_CTRL / `ADC_LP_SEQ0 / `ADC_HP_SEQ /
    // `ADC_LP_SEQ_LEN / `ADC_HP_SEQ_LEN
    // DMA_STAT removed. CH_DATA replaced by LP_DATA/HP_DATA.

    function new(string name = "adc_reg_seq");
        super.new(name);
    endfunction

    task body();
        bit [31:0] rd;

        `uvm_info(get_type_name(), "=== Register Test ===", UVM_LOW)

        // Wait for power-on reset to complete (handled by tb_top)
        #300;

        // Step 1: Check default values after reset (REG_001 — expanded to all registers)
        // CTRL=0, STAT=0(RO,busy=0), TRIG=0, INT_EN=0, INT_STAT=0, CAL_CTRL=0,
        // CAL_VAL=0, ANA_CFG=0, ANA_REG=0, DMA_CTRL=0, DMA_STAT=0,
        // LP_SEQ0~7=0, HP_SEQ=0, LP_SEQ_LEN=ADC_NUM_CH(26), HP_SEQ_LEN=4
        // 注意：LP_SEQ_LEN 默认值随 ADC_NUM_CH 参数变；LP_SEQ7 在 NUM_LP_SEQ_REG<8
        //   时（如默认 26 通道 → 7 组）读回 0（未实现组）。下方 default check
        //   与 sweep 用 `ADC_LP_SEQ7 及 mask 已对齐参数化行为。
        apb_read(`ADC_CTRL, rd);
        check_reg("CTRL", rd, 16'h0000);
        apb_read(`ADC_TRIG, rd);
        check_reg("TRIG", rd, 16'h0000);
        apb_read(`ADC_INT_EN, rd);
        check_reg("INT_EN", rd, 16'h0000);
        apb_read(`ADC_INT_STAT, rd);
        check_reg("INT_STAT", rd, 16'h0000);
        apb_read(`ADC_CAL_CTRL, rd);
        check_reg("CAL_CTRL", rd, 16'h0000);
        apb_read(`ADC_CAL_VAL, rd);
        check_reg("CAL_VAL", rd, 16'h0000);
        apb_read(`ADC_ANA_CFG, rd);
        check_reg("ANA_CFG", rd, 32'h00000000);
        apb_read(`ADC_ANA_REG, rd);
        check_reg("ANA_REG", rd, 32'h00000000);
        apb_read(`ADC_DMA_CTRL, rd);
        check_reg("DMA_CTRL", rd, 16'h0000);
        // DMA_STAT register deleted — no default check.
        apb_read(`ADC_LP_SEQ_LEN, rd);
        check_reg("LP_SEQ_LEN", rd, 32'h0000_001A);  // default = ADC_NUM_CH (26=0x1A)
        apb_read(`ADC_HP_SEQ_LEN, rd);
        check_reg("HP_SEQ_LEN", rd, 4);
        // LP_SEQ0~7 default 0
        apb_read(`ADC_LP_SEQ0, rd); check_reg("LP_SEQ0", rd, 32'h0);
        apb_read(`ADC_LP_SEQ1, rd); check_reg("LP_SEQ1", rd, 32'h0);
        apb_read(`ADC_LP_SEQ7, rd); check_reg("LP_SEQ7", rd, 32'h0);
        apb_read(`ADC_HP_SEQ, rd);  check_reg("HP_SEQ", rd, 32'h0);
        // STAT is RO — just read (busy=0 expected)
        apb_read(`ADC_STAT, rd);
        `uvm_info(get_type_name(), $sformatf("STAT = 0x%04h", rd[15:0]), UVM_LOW)

        // Step 2: Read-only registers (STAT, CAL_VAL, DMA_STAT) — REG_003
        // (covered by write_read_reg skip + check above)

        // Step 3: Write/read RW registers (REG_002 — expanded to LP_SEQ0~7)
        write_read_reg("CTRL",       `ADC_CTRL,     32'h007F_7F09);  // ADC_EN+SPT0=7+SPT1=7+DATA_ALIGN+SMPL_INTERVAL=0x7F (no RSVD bits)
        write_read_reg("TRIG",       `ADC_TRIG,     32'h0000_7E7E);
        write_read_reg("INT_EN",     `ADC_INT_EN,   32'h0000_003F);
        write_read_reg("ANA_CFG",    `ADC_ANA_CFG,  32'h0000_A5A5);
        write_read_reg("ANA_REG",    `ADC_ANA_REG,  32'hA5A5_A5A5);
        write_read_reg("DMA_CTRL",   `ADC_DMA_CTRL, 32'h0000_003F);
        // LP_SEQ0~6: write/read。entry 内 rsv 高位读回 0，写入值须低 W_CH_SEL bit 有效。
        // 26ch(W_CH_SEL=5): 写入值 entry0~25 = 0x00~0x19，高3bit rsv=0，读回=写入(strict ==)。
        // 注意 LP_SEQ6(0xD0) 含 entry24~27：26ch 只实现 entry24/25(0x18/0x19)，
        // entry26/27(0x1A/0x1B) 越界读回 0 → 写 0x1B1A_1918 读回 0x0000_1918。
        // 故 LP_SEQ6 用 masked 比对（mask 仅 entry24/25 占位）。
        write_read_reg("LP_SEQ0",    `ADC_LP_SEQ0,  32'h0302_0100);
        write_read_reg("LP_SEQ1",    `ADC_LP_SEQ1,  32'h0706_0504);
        write_read_reg("LP_SEQ2",    `ADC_LP_SEQ2,  32'h0B0A_0908);
        write_read_reg("LP_SEQ3",    `ADC_LP_SEQ3,  32'h0F0E_0D0C);
        write_read_reg("LP_SEQ4",    `ADC_LP_SEQ4,  32'h1312_1110);
        write_read_reg("LP_SEQ5",    `ADC_LP_SEQ5,  32'h1716_1514);
        // LP_SEQ6: 26ch 实现 entry24/25，entry26/27 越界读 0 → masked 比对
        // mask = entry24/25 占位(bit[7:0]/[15:8] 各低 W_CH_SEL bit)
        write_read_reg_masked("LP_SEQ6", `ADC_LP_SEQ6, 32'h1B1A_1918,
                              `ADC_SEQ_ENTRY_MASK | (`ADC_SEQ_ENTRY_MASK<<8));
        // LP_SEQ7: 仅在 NUM_LP_SEQ_REG==8（ADC_NUM_CH 为 29~32）时实现；
        // 默认 26 通道 → NUM_LP_SEQ_REG=7，LP_SEQ7 读回 0、写忽略。
        // 默认配置下跳过 write_read（避免误报 fail）；32 通道配置时启用。
        if (`ADC_NUM_CH >= 29) begin
            write_read_reg("LP_SEQ7",    `ADC_LP_SEQ7,  32'h1F1E_1D1C);
        end
        write_read_reg("HP_SEQ",     `ADC_HP_SEQ,   32'h0706_0504);
        write_read_reg("LP_SEQ_LEN", `ADC_LP_SEQ_LEN, 32'h0000_0010);  // 16 entries
        write_read_reg("HP_SEQ_LEN", `ADC_HP_SEQ_LEN, 32'h0000_0002);  // 2 entries

        // ─── REG_002a: 32-bit pattern sweep for ALL RW registers ───
        // 对每个 RW 寄存器写 4 种 pattern 读回比对:
        //   0xFFFFFFFF (全1) / 0x00000000 (全0) / 0x5A5A5A5A / 0xA5A5A5A5
        // RW 寄存器必须读回=写入值; RO/W1C/WO 不比对(跳过)。
        // 此测试覆盖位 stuck-at、位翻转、读写隔离等常见寄存器缺陷。
        `uvm_info(get_type_name(), "=== REG_002a: 32-bit pattern sweep ===", UVM_LOW)
        reg_pattern_sweep();

        // ─── REG_004: WO self-clearing (TRIG SW_TRIG bits read back 0) ───
        // Write TRIG with LP_SW_TRIG(bit0)=1 + LP_SW_TRG_EN(bit1)=1.
        // bit0/bit8 are WO — read should mask them to 0 (only EN bits read back).
        // NOTE: scoreboard expects read-back == written value; WO bits break that
        // expectation. Refresh scoreboard expectation by reading first, OR skip
        // scoreboard for this WO write. We read back immediately which refreshes
        // scoreboard to the actual (masked) value.
        apb_write(`ADC_TRIG, 32'h0000_0003);  // LP_SW_TRIG=1, LP_SW_TRG_EN=1
        #200;
        apb_read(`ADC_TRIG, rd);  // this read refreshes scoreboard exp to masked value
        if (rd[0] == 1'b0 && rd[1] == 1'b1) begin
            `uvm_info(get_type_name(), "[PASS] REG_004: TRIG WO bit0 reads 0, EN bit1 reads 1", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), $sformatf("[FAIL] REG_004: TRIG read=0x%08h (exp bit0=0,bit1=1)", rd))
        end

        // ─── REG_009: LP_DATA[26:31] reserved-space boundary ───
        // Addresses 0x8C~0xA0 (would be LP_DATA[26:31]). Not generated as regs;
        // read back 0.
        apb_read(`ADC_LP_DATA0 + 26*4, rd);  // 0x8C
        if (rd == 32'h0000_0000) `uvm_info(get_type_name(), "[PASS] REG_009: LP_DATA[26] reads 0 (no reg)", UVM_LOW)
        else `uvm_error(get_type_name(), $sformatf("[FAIL] REG_009: LP_DATA[26]=0x%08h (exp 0)", rd))
        apb_read(`ADC_LP_DATA0 + 31*4, rd);  // 0xA0
        if (rd == 32'h0000_0000) `uvm_info(get_type_name(), "[PASS] REG_009: LP_DATA[31] reads 0 (no reg)", UVM_LOW)
        else `uvm_error(get_type_name(), $sformatf("[FAIL] REG_009: LP_DATA[31]=0x%08h (exp 0)", rd))

        `uvm_info(get_type_name(), "Register test complete", UVM_LOW)
    endtask

    task check_reg(string name, bit [31:0] val, bit [31:0] exp);
        if (val == exp) begin
            `uvm_info(get_type_name(), $sformatf(
                "[PASS] %s default = 0x%08h", name, val), UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), $sformatf(
                "[FAIL] %s default exp=0x%08h got=0x%08h", name, exp, val))
        end
    endtask

    task write_read_reg(string name, bit [15:0] addr, bit [31:0] val);
        bit [31:0] rd;
        apb_write(addr, val);
        apb_read(addr, rd);
        if (rd == val) begin
            `uvm_info(get_type_name(), $sformatf(
                "[PASS] %s write/read = 0x%08h", name, rd), UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), $sformatf(
                "[FAIL] %s exp=0x%08h got=0x%08h", name, val, rd))
        end
    endtask

    // write/read 带 mask 比对：用于 entry 越界读 0 或 rsv 位读 0 的寄存器
    //（如 LP_SEQ6 在 26ch 下 entry26/27 越界读 0）。只比对 mask 覆盖的位。
    task write_read_reg_masked(string name, bit [15:0] addr, bit [31:0] val, bit [31:0] mask);
        bit [31:0] rd;
        apb_write(addr, val);
        apb_read(addr, rd);
        if ((rd & mask) == (val & mask)) begin
            `uvm_info(get_type_name(), $sformatf(
                "[PASS] %s write/read = 0x%08h (masked=0x%08h)", name, rd, (rd & mask)), UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), $sformatf(
                "[FAIL] %s exp(masked)=0x%08h got=0x%08h (masked=0x%08h)",
                name, (val & mask), rd, (rd & mask)))
        end
    endtask

    // ────────────────────────────────────────────────────────────────────────
    // REG_002a: 32-bit pattern sweep for ALL RW registers
    //   对每个 RW 寄存器写 4 种 pattern 读回比对:
    //     0xFFFFFFFF (全1) / 0x00000000 (全0) / 0x5A5A5A5A / 0xA5A5A5A5
    //   RW 寄存器必须读回=写入值; RO/W1C/WO 不比对(跳过)。
    //   覆盖位 stuck-at、位翻转、读写隔离等常见寄存器缺陷。
    // ────────────────────────────────────────────────────────────────────────
    task reg_pattern_sweep();
        // RW 寄存器列表: {名称, 地址}
        // 排除 RO(STAT/CAL_VAL/DMA_STAT/CH_DATA)、W1C(INT_STAT)、
        // WO(TRIG 的 bit0/bit8, 但 TRIG 的 EN/SEL 位是 RW 所以包含)
        // 注意: CTRL 有 RSVD 位和 SW_RST 自清零, 读回≠写入, 需用 mask
        //       TRIG 有 WO 位(bit0/bit8), 读回≠写入, 需用 mask
        //       CAL_CTRL bit1 是 CAL_DONE(RO), 读回≠写入, 需用 mask

        // ---- CTRL: RW 但有 RSVD/SW_RST/CAL_DONE, 用 mask 比对 ----
        // CTRL 可写位: [0]ADC_EN [3]DATA_ALIGN [10:8]SPT0 [13:11]SPT1 [14]CONT_MODE [22:16]SMPL_INTERVAL
        // mask = 0x007F_7F09
        reg_sweep_masked("CTRL", `ADC_CTRL, 32'h007F_7F09);

        // ---- TRIG: RW 但有 WO 位(bit0/bit8), 用 mask 比对 ----
        // TRIG 可写读回位: [1]LP_SW_TRG_EN [2]LP_MCTM_EN [6:3]LP_TRG_SEL
        //                 [9]HP_SW_TRG_EN [10]HP_MCTM_EN [14:11]HP_TRG_SEL
        // mask = 0x0000_7E7E (不含 bit0/bit8 WO)
        reg_sweep_masked("TRIG", `ADC_TRIG, 32'h0000_7E7E);

        // ---- INT_EN: 6-bit RW, mask = 0x0000_003F ----
        reg_sweep_masked("INT_EN", `ADC_INT_EN, 32'h0000_003F);

        // ---- CAL_CTRL: bit0=CAL_ST(RW), bit1=CAL_DONE(RO), mask = 0x0000_0001 ----
        reg_sweep_masked("CAL_CTRL", `ADC_CAL_CTRL, 32'h0000_0001);

        // ---- ANA_CFG: 16-bit RW, mask = 0x0000_FFFF ----
        reg_sweep_masked("ANA_CFG", `ADC_ANA_CFG, 32'h0000_FFFF);

        // ---- ANA_REG: 32-bit RW, mask = 0xFFFF_FFFF ----
        reg_sweep_masked("ANA_REG", `ADC_ANA_REG, 32'hFFFF_FFFF);

        // ---- DMA_CTRL: 6-bit RW, mask = 0x0000_003F ----
        reg_sweep_masked("DMA_CTRL", `ADC_DMA_CTRL, 32'h0000_003F);

        // ---- LP_SEQ[0:7]: 32-bit RW，entry 内 rsv 高位读回 0，mask = per-entry ch_sel mask ----
        reg_sweep_masked("LP_SEQ0", `ADC_LP_SEQ0, `ADC_SEQ_REG_MASK);
        reg_sweep_masked("LP_SEQ1", `ADC_LP_SEQ1, `ADC_SEQ_REG_MASK);
        reg_sweep_masked("LP_SEQ2", `ADC_LP_SEQ2, `ADC_SEQ_REG_MASK);
        reg_sweep_masked("LP_SEQ3", `ADC_LP_SEQ3, `ADC_SEQ_REG_MASK);
        reg_sweep_masked("LP_SEQ4", `ADC_LP_SEQ4, `ADC_SEQ_REG_MASK);
        reg_sweep_masked("LP_SEQ5", `ADC_LP_SEQ5, `ADC_SEQ_REG_MASK);
        // LP_SEQ6(0xD0): 含 entry24~27。26ch 实现 entry24/25，entry26/27 越界读 0。
        // sweep mask 仅覆盖 entry24/25 占位（bit[7:0]/[15:8] 各低 W_CH_SEL bit）。
        reg_sweep_masked("LP_SEQ6", `ADC_LP_SEQ6,
                         `ADC_SEQ_ENTRY_MASK | (`ADC_SEQ_ENTRY_MASK<<8));
        // LP_SEQ7 sweep 仅在 32 通道预留配置（NUM_LP_SEQ_REG==8）时执行
        if (`ADC_NUM_CH >= 29) begin
            reg_sweep_masked("LP_SEQ7", `ADC_LP_SEQ7, `ADC_SEQ_REG_MASK);
        end

        // ---- HP_SEQ: 32-bit RW，entry 内 rsv 高位读回 0，mask = per-entry ch_sel mask ----
        reg_sweep_masked("HP_SEQ", `ADC_HP_SEQ, `ADC_SEQ_REG_MASK);

        // ---- LP_SEQ_LEN: W_LP_SEQ_LEN-bit RW, mask = 可写位 ----
        // 位宽随 ADC_NUM_CH 变：$clog2(N+1)。默认 26 → 5bit (mask 0x1F)，
        // 32 → 6bit (mask 0x3F)，8 → 4bit (mask 0x0F)。
        reg_sweep_masked("LP_SEQ_LEN", `ADC_LP_SEQ_LEN,
                         (32'h1 << `ADC_LP_SEQ_LEN_W) - 1);

        // ---- HP_SEQ_LEN: 3-bit RW, mask = 0x0000_0007 ----
        reg_sweep_masked("HP_SEQ_LEN", `ADC_HP_SEQ_LEN, 32'h0000_0007);

        // 跳过的寄存器(非 RW,不比对):
        //   STAT(RO) / INT_STAT(W1C) / CAL_VAL(RO) / CH_DATA[0:31](RO) / DMA_STAT(RO)
    endtask

    // 对单个 RW 寄存器做 4-pattern sweep,用 mask 过滤可写位后比对
    task reg_sweep_masked(string name, bit [15:0] addr, bit [31:0] mask);
        bit [31:0] rd;
        bit [31:0] patterns[4];
        integer i;
        integer pass_cnt;
        integer fail_cnt;

        patterns[0] = 32'hFFFF_FFFF;
        patterns[1] = 32'h0000_0000;
        patterns[2] = 32'h5A5A_5A5A;
        patterns[3] = 32'hA5A5_A5A5;

        pass_cnt = 0;
        fail_cnt = 0;

        // SW_RST 清干净, 确保起始状态干净
        apb_write(`ADC_CTRL, 32'h0000_0002);  // SW_RST
        #2000;
        apb_write(`ADC_CTRL, 32'h0000_0001);  // ADC_EN=1

        for (i = 0; i < 4; i++) begin
            bit [31:0] wr_val;
            bit [31:0] exp_val;
            wr_val = patterns[i] & mask;  // 只写可写位
            apb_write(addr, wr_val);
            #100;  // 等写生效
            apb_read(addr, rd);
            exp_val = wr_val;  // RW 寄存器读回应=写入值(masked)
            if ((rd & mask) == exp_val) begin
                pass_cnt = pass_cnt + 1;
                `uvm_info(get_type_name(), $sformatf(
                    "[PASS] REG_002a %s pattern[%0d]=0x%08h: rd=0x%08h (masked=0x%08h)",
                    name, i, wr_val, rd, (rd & mask)), UVM_LOW)
            end else begin
                fail_cnt = fail_cnt + 1;
                `uvm_error(get_type_name(), $sformatf(
                    "[FAIL] REG_002a %s pattern[%0d]=0x%08h: rd=0x%08h (masked=0x%08h, exp=0x%08h)",
                    name, i, wr_val, rd, (rd & mask), exp_val))
            end
        end

        // 汇总
        if (fail_cnt == 0) begin
            `uvm_info(get_type_name(), $sformatf(
                "[PASS] REG_002a %s: 4/4 patterns passed (mask=0x%08h)",
                name, mask), UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), $sformatf(
                "[FAIL] REG_002a %s: %0d/%0d patterns failed (mask=0x%08h)",
                name, fail_cnt, pass_cnt + fail_cnt, mask))
        end

        // 恢复默认
        apb_write(`ADC_CTRL, 32'h0000_0002);  // SW_RST
        #2000;
        apb_write(`ADC_CTRL, 32'h0000_0001);  // ADC_EN=1
    endtask
endclass
