class adc_sequence_seq extends adc_base_seq;
    `uvm_object_utils(adc_sequence_seq)

    rand bit [4:0] channels[3];

    constraint c_channels {
        channels[0] != channels[1];
        channels[1] != channels[2];
        channels[2] != channels[0];
        channels[0] inside {[0:25]};
        channels[1] inside {[0:25]};
        channels[2] inside {[0:25]};
    }

    function new(string name = "adc_sequence_seq");
        super.new(name);
    endfunction

    task body();
        bit [31:0] rd;

        `uvm_info(get_type_name(), "=== Sequence Sample Test ===", UVM_LOW)

        // Randomize channels (rand constraint: 3 distinct channels 0~25)
        void'(randomize());

        // Wait for power-on reset
        #300;

        // SW_RST to ensure clean state before testing (analog model + FSM)
        apb_write(`ADC_CTRL, 32'h0000_0002);
        #2000;
        apb_write(`ADC_CTRL, 32'h0000_0001);
        #200;

        // ─── SMP_002: 3-channel sequence {CH5, CH10, CH15} (testplan-specified) ───
        // Use fixed channels per testplan (not the randomized ones) for SMP_002.
        // The randomized channels[] remain for coverage variety but the named
        // testplan case uses the spec-defined set.
        `uvm_info(get_type_name(), "=== SMP_002: LP_SEQ={CH5,CH10,CH15} ===", UVM_LOW)
        apb_write(`ADC_LP_SEQ0, 32'h000F0A05);  // ENT0=CH5, ENT1=CH10, ENT2=CH15
        apb_write(`ADC_LP_SEQ1, 32'h00000000);
        apb_write(`ADC_LP_SEQ2, 32'h00000000);
        apb_write(`ADC_LP_SEQ3, 32'h00000000);
        apb_write(`ADC_LP_SEQ4, 32'h00000000);
        apb_write(`ADC_LP_SEQ5, 32'h00000000);
        apb_write(`ADC_LP_SEQ6, 32'h00000000);
        apb_write(`ADC_LP_SEQ7, 32'h00000000);
        apb_write(`ADC_LP_SEQ_LEN, 32'h0000_0003);
        #100;
        apb_write(`ADC_TRIG, 32'h0000_0000);
        apb_write(`ADC_TRIG, 32'h0000_0002);
        apb_write(`ADC_TRIG, 32'h0000_0003);
        #50000;
        // Check the 3 spec-defined channels — written to LP_DATA[0..2]
        apb_read(`ADC_LP_DATA0 + 0*4, rd);
        if (rd[31]) `uvm_info(get_type_name(), "[PASS] SMP_002: LP_DATA[0] (CH5) VALID=1", UVM_LOW)
        else `uvm_error(get_type_name(), "[FAIL] SMP_002: LP_DATA[0] VALID=0")
        apb_read(`ADC_LP_DATA0 + 1*4, rd);
        if (rd[31]) `uvm_info(get_type_name(), "[PASS] SMP_002: LP_DATA[1] (CH10) VALID=1", UVM_LOW)
        else `uvm_error(get_type_name(), "[FAIL] SMP_002: LP_DATA[1] VALID=0")
        apb_read(`ADC_LP_DATA0 + 2*4, rd);
        if (rd[31]) `uvm_info(get_type_name(), "[PASS] SMP_002: LP_DATA[2] (CH15) VALID=1", UVM_LOW)
        else `uvm_error(get_type_name(), "[FAIL] SMP_002: LP_DATA[2] VALID=0")

        // ─── SMP_003: 26-channel full sequence ───
        // Configure LP_SEQ[0:6] with 26 channels (CH0~CH25), LP_SEQ_LEN=26.
        // 8 entries per register × 7 registers (LP_SEQ0~6) = 56 slots, use first 26.
        // CH0~CH7 in LP_SEQ0, CH8~CH15 in LP_SEQ1, ..., CH24~CH25 in LP_SEQ6[7:0]/[15:8].
        `uvm_info(get_type_name(), "=== SMP_003: 26-channel full sequence ===", UVM_LOW)
        apb_write(`ADC_CTRL, 32'h0000_0002); #2000;  // SW_RST
        apb_write(`ADC_CTRL, 32'h0000_0001); #200;   // re-enable
        // 32-bit reg holds 4 entries: LP_SEQ0 = {ENT3,ENT2,ENT1,ENT0}
        apb_write(`ADC_LP_SEQ0, {8'd3, 8'd2, 8'd1, 8'd0});           // CH0,1,2,3
        apb_write(`ADC_LP_SEQ1, {8'd7, 8'd6, 8'd5, 8'd4});           // CH4,5,6,7
        apb_write(`ADC_LP_SEQ2, {8'd11, 8'd10, 8'd9, 8'd8});         // CH8,9,10,11
        apb_write(`ADC_LP_SEQ3, {8'd15, 8'd14, 8'd13, 8'd12});       // CH12,13,14,15
        apb_write(`ADC_LP_SEQ4, {8'd19, 8'd18, 8'd17, 8'd16});       // CH16,17,18,19
        apb_write(`ADC_LP_SEQ5, {8'd23, 8'd22, 8'd21, 8'd20});       // CH20,21,22,23
        apb_write(`ADC_LP_SEQ6, {8'h1F, 8'h1F, 8'd25, 8'd24});       // CH24,25, then 0x1F stop
        apb_write(`ADC_LP_SEQ7, 32'h1F1F1F1F);
        apb_write(`ADC_LP_SEQ_LEN, 32'h0000_001A);  // 26
        #100;
        apb_write(`ADC_TRIG, 32'h0000_0000);
        apb_write(`ADC_TRIG, 32'h0000_0002);
        apb_write(`ADC_TRIG, 32'h0000_0003);
        #500000;  // 26 samples × ~5.6us each ≈ 145us; wait generously
        // Spot-check a few slots across the 26-entry range (slot 0, 13, 25)
        apb_read(`ADC_LP_DATA0 + 0*4, rd);
        if (rd[31]) `uvm_info(get_type_name(), "[PASS] SMP_003: LP_DATA[0] (CH0) VALID=1", UVM_LOW)
        else `uvm_error(get_type_name(), "[FAIL] SMP_003: LP_DATA[0] VALID=0")
        apb_read(`ADC_LP_DATA0 + 13*4, rd);
        if (rd[31]) `uvm_info(get_type_name(), "[PASS] SMP_003: LP_DATA[13] (CH13) VALID=1", UVM_LOW)
        else `uvm_error(get_type_name(), "[FAIL] SMP_003: LP_DATA[13] VALID=0")
        apb_read(`ADC_LP_DATA0 + 25*4, rd);
        if (rd[31]) `uvm_info(get_type_name(), "[PASS] SMP_003: LP_DATA[25] (CH25) VALID=1 (last)", UVM_LOW)
        else `uvm_error(get_type_name(), "[FAIL] SMP_003: LP_DATA[25] VALID=0")

        // ─── SMP_012: LP sequence complete → HP sequence ───
        `uvm_info(get_type_name(), "=== SMP_012: LP then HP sequence ===", UVM_LOW)
        apb_write(`ADC_CTRL, 32'h0000_0002); #2000;
        apb_write(`ADC_CTRL, 32'h0000_0001); #200;
        // LP 2 channels
        apb_write(`ADC_LP_SEQ0, 32'h00000100);  // CH0, CH1
        apb_write(`ADC_LP_SEQ1, 32'h00000000);
        apb_write(`ADC_LP_SEQ2, 32'h00000000);
        apb_write(`ADC_LP_SEQ3, 32'h00000000);
        apb_write(`ADC_LP_SEQ4, 32'h00000000);
        apb_write(`ADC_LP_SEQ5, 32'h00000000);
        apb_write(`ADC_LP_SEQ6, 32'h00000000);
        apb_write(`ADC_LP_SEQ7, 32'h00000000);
        apb_write(`ADC_LP_SEQ_LEN, 32'h0000_0002);
        // HP 2 channels
        apb_write(`ADC_HP_SEQ, 32'h00000100);  // CH0, CH1
        apb_write(`ADC_HP_SEQ_LEN, 32'h0000_0002);
        #100;
        // Trigger LP first
        apb_write(`ADC_TRIG, 32'h0000_0002);
        apb_write(`ADC_TRIG, 32'h0000_0003);
        #15000;  // LP sequence done
        // Now trigger HP
        apb_write(`ADC_TRIG, 32'h0000_0200);
        apb_write(`ADC_TRIG, 32'h0000_0300);
        #15000;
        apb_read(`ADC_LP_DATA0 + 0*4, rd);
        if (rd[31]) `uvm_info(get_type_name(), "[PASS] SMP_012: LP+HP LP_DATA[0] VALID", UVM_LOW)
        else `uvm_error(get_type_name(), "[FAIL] SMP_012: LP_DATA[0] not sampled")
        apb_read(`ADC_LP_DATA0 + 1*4, rd);
        if (rd[31]) `uvm_info(get_type_name(), "[PASS] SMP_012: LP+HP LP_DATA[1] VALID", UVM_LOW)
        else `uvm_error(get_type_name(), "[FAIL] SMP_012: LP_DATA[1] not sampled")

        `uvm_info(get_type_name(), "Sequence sample test complete", UVM_LOW)
    endtask
endclass

