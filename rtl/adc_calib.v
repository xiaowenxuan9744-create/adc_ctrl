//*********************** Module Header ***************************************
// Module        : adc_calib
// Description   : Deprecated — calibration logic now lives entirely in the
//                 register file (PCLK domain):
//                   - cal_st  : plain RW bit → cfg_cal_st → analog
//                   - cal_done: analog input, 2-stage synced in regfile (cal_done_s1/s2)
//                   - cal_val : latched in regfile when cal_done_s2=1
//                   - cal_busy: derived in adc_top as cfg_cal_st & ~cal_done
//                 This module is no longer instantiated by adc_top and has
//                 been removed from all filelists (rtl/filelist.f, rtl.flist,
//                 Makefile unit-TB list). Retained on disk only as a
//                 historical stub; safe to delete the file in a future cleanup.
//******************************************************************************

module adc_calib #(
    parameter P_SHELL_MODE = 0
) (
    input  wire        adc_clkn,
    input  wire        rst_adc_n,
    input  wire        cal_st_set,
    input  wire        cal_done_i,
    input  wire [5:0]  cal_val_i,
    output wire        cal_st_o,
    output wire        cal_st_r_o,
    output wire        cal_done,
    output wire [5:0]  cal_val,
    output wire        cal_busy
);

    // Unused. Outputs held at safe values.
    wire _unused = &{1'b0, adc_clkn, rst_adc_n, cal_st_set, cal_done_i,
                     cal_val_i, P_SHELL_MODE};

    assign cal_st_o   = 1'b0;
    assign cal_st_r_o = 1'b0;
    assign cal_done   = 1'b0;
    assign cal_val    = 6'h00;
    assign cal_busy   = 1'b0;

endmodule
