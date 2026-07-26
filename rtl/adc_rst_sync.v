//*********************** Module Header ***************************************
// Module        : adc_rst_sync
// Description   : Asynchronous reset synchronizer (2-stage)
//                 Reset assertion is asynchronous (immediate).
//                 Reset de-assertion is synchronized to destination clock.
// Clock         : clk
// Reset         : async_rst_n (asynchronous, active low)
// Parameters:
//   P_SHELL_MODE — 1=shell mode, all outputs tied to safe values
//******************************************************************************

module adc_rst_sync #(
    parameter P_SHELL_MODE = 0
) (
    input  wire clk,
    input  wire async_rst_n,

    output wire sync_rst_n
);

    //==========================================================================
    // Shell Mode
    //==========================================================================
    generate
        if (P_SHELL_MODE) begin : gen_shell

            assign sync_rst_n = 1'b1;

        end else begin : gen_active

            //==========================================================================
            // Internal Signals
            //==========================================================================
            reg sync_ff1;
            reg sync_ff2;

            //==========================================================================
            // 2-Stage Reset Synchronizer
            //==========================================================================
            // seq logic
            // First stage D is tied to 1'b1 (VDD).
            // When async_rst_n is asserted, both flops reset to 0 immediately.
            // When async_rst_n de-asserts, logic-1 propagates through two stages.
            always @(posedge clk or negedge async_rst_n) begin
                if (!async_rst_n) begin
                    sync_ff1 <= 1'b0;
                    sync_ff2 <= 1'b0;
                end else begin
                    sync_ff1 <= 1'b1;
                    sync_ff2 <= sync_ff1;
                end
            end

            assign sync_rst_n = sync_ff2;

        end
    endgenerate

endmodule
