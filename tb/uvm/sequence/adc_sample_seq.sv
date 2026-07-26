// ============================================================================
// Sequence: adc_sample_seq
// Description: Software trigger single-sample sequence
//              1. Wait for power-on reset
//              2. Configure LP_SEQ for single channel
//              3. Enable ADC
//              4. Software trigger → wait EOC → read LP_DATA
// ============================================================================

class adc_sample_seq extends adc_base_seq;
    `uvm_object_utils(adc_sample_seq)

    rand bit [4:0]  channel;
    rand bit [2:0]  spt;
    rand bit [3:0]  interval;
    rand bit [1:0]  align;

    constraint c_channel {
        channel inside {[0:25]};
    }

    function new(string name = "adc_sample_seq");
        super.new(name);
    endfunction

    task body();
        bit [31:0] rd, stat;

        `uvm_info(get_type_name(), "=== Single Sample Test ===", UVM_LOW)

        // Wait for power-on reset to complete (tb_top handles this)
        #300;

        // Enable ADC:
        //   [0]    = ADC_EN = 1
        //   [1]    = SW_RST = 0
        //   [2]    = reserved = 0
        //   [3]    = DATA_ALIGN = align[0]
        //   [7:4]  = SMPL_INTERVAL = interval
        //   [10:8] = SPT0 = spt
        //   [13:11]= SPT1 = 0
        //   [14]   = CONT_MODE = 0
        apb_write(`ADC_CTRL, {17'h00000, 1'b0, 3'h0, spt, interval, align[0], 1'b0, 1'b0, 1'b1});
        #200;

        // Write LP_SEQ0: single channel entry
        apb_write(`ADC_LP_SEQ0, {24'h000000, channel});
        apb_write(`ADC_LP_SEQ1, 32'h00000000);
        apb_write(`ADC_LP_SEQ2, 32'h00000000);
        apb_write(`ADC_LP_SEQ3, 32'h00000000);
        apb_write(`ADC_LP_SEQ4, 32'h00000000);
        apb_write(`ADC_LP_SEQ5, 32'h00000000);
        apb_write(`ADC_LP_SEQ6, 32'h00000000);
        apb_write(`ADC_LP_SEQ7, 32'h00000000);

        // Set LP_SEQ_LEN=1 so only 1 conversion occurs
        apb_write(`ADC_LP_SEQ_LEN, 32'h0000_0001);
        #100;

        // Clear and trigger: write LP_SW_TRG_EN, then LP_SW_TRIG
        apb_write(`ADC_TRIG, 32'h0000_0002);  // LP_SW_TRG_EN only
        apb_write(`ADC_TRIG, 32'h0000_0003);  // LP_SW_TRIG + LP_SW_TRG_EN

        // Wait for sampling to complete
        // SPT(3) + conv(14) = 17 ADC cycles @40ns = 680ns. Wait 5000ns for margin.
        #5000;

        // Read slot 0 of the LP sequence (write_lp_seq_single puts the channel
        // in ENT0, so LP_DATA[0] holds the result).
        apb_read(`ADC_LP_DATA0, rd);
        if (rd[31]) begin
            `uvm_info(get_type_name(), $sformatf(
                "[PASS] LP slot 0 (CH%0d) VALID=1 data=0x%04h", channel, rd[15:0]), UVM_LOW)
        end else begin
            `uvm_error(get_type_name(), $sformatf(
                "[FAIL] CH%0d VALID=0", channel))
        end

        `uvm_info(get_type_name(), "Single sample test complete", UVM_LOW)
    endtask
endclass


// ============================================================================
// Sequence: adc_sequence_seq
// Description: Multi-channel sequence sampling
// ============================================================================

