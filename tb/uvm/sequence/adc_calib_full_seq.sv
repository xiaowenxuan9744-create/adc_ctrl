// ============================================================================
// Sequence: adc_calib_full_seq
// Description: Remaining calibration tests
//              CAL_004: Re-calibration (write CAL_ST=0 then CAL_ST=1 again)
//              CAL_005: Calibration ignored path sanity (ADC_EN=0 keeps cal_done=0)
//
//              Calibration is auto-driven by the hardware analog model. The
//              sequence only triggers calibration and polls the registers.
// ============================================================================

class adc_calib_full_seq extends adc_base_seq;
    `uvm_object_utils(adc_calib_full_seq)

    function new(string name = "adc_calib_full_seq");
        super.new(name);
    endfunction

    task wait_cal_done(input integer max_poll);
        bit [31:0] rd;
        integer n;
        n = 0;
        forever begin
            apb_read(`ADC_CAL_CTRL, rd);
            if (rd[1]) return;
            n = n + 1;
            if (n > max_poll) begin
                `uvm_error(get_type_name(), "[FAIL] CAL_DONE not observed (timeout)")
                return;
            end
            #200;
        end
    endtask

    task body();
        bit [31:0] rd;
        `uvm_info(get_type_name(), "=== Full Calibration Test ===", UVM_LOW)
        #300;

        apb_write(`ADC_CTRL, 32'h0000_0001);  // ADC_EN=1
        #200;

        // --- CAL_004: Re-calibration ---
        // First calibration
        apb_write(`ADC_CAL_CTRL, 32'h0000_0001);  // CAL_ST=1
        wait_cal_done(50);
        apb_read(`ADC_CAL_VAL, rd);
        if (rd[5:0] == 6'h2A) begin
            `uvm_info(get_type_name(), "[PASS] CAL_004a: first CAL_VAL = 0x2A", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), $sformatf("[FAIL] CAL_004a: CAL_VAL=0x%02h", rd[5:0]))
        end

        // Clear CAL_ST=0 → analog clears cal_done, re-arm
        apb_write(`ADC_CAL_CTRL, 32'h0000_0000);
        #500;
        // Re-calibrate: CAL_ST=1 again (no reset needed)
        apb_write(`ADC_CAL_CTRL, 32'h0000_0001);
        wait_cal_done(50);
        apb_read(`ADC_CAL_VAL, rd);
        if (rd[5:0] == 6'h2A) begin
            `uvm_info(get_type_name(), "[PASS] CAL_004b: re-cal CAL_VAL = 0x2A (no reset needed)", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), $sformatf("[FAIL] CAL_004b: re-cal CAL_VAL=0x%02h", rd[5:0]))
        end
        // Clean up: clear CAL_ST
        apb_write(`ADC_CAL_CTRL, 32'h0000_0000);
        #500;

        // --- CAL_005: ADC_EN=0 keeps cal_done=0 ---
        // With ADC_EN=0, asserting CAL_ST must NOT produce cal_done (analog
        // clears cal_done when ADC_EN=0).
        apb_write(`ADC_CTRL, 32'h0000_0000);  // ADC_EN=0
        #200;
        apb_write(`ADC_CAL_CTRL, 32'h0000_0001);  // CAL_ST=1 (ignored because ADC_EN=0)
        #3000;  // well beyond 20-cycle calibration time
        apb_read(`ADC_CAL_CTRL, rd);
        if (!rd[1]) begin
            `uvm_info(get_type_name(), "[PASS] CAL_005: no CAL_DONE while ADC_EN=0", UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), "[FAIL] CAL_005: CAL_DONE asserted with ADC_EN=0")
        end
        apb_write(`ADC_CAL_CTRL, 32'h0000_0000);  // clean up CAL_ST
        #200;

        `uvm_info(get_type_name(), "Full calibration test complete", UVM_LOW)
    endtask
endclass
