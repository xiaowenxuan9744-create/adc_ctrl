//*********************** Module Header ***************************************
// Module        : adc_sync_cell
// Description   : 2-stage CDC synchronizer with optional rising edge detection
//                 EDGE_DETECT=0 (default): pure 2-stage sync, rise_detect=0
//                 EDGE_DETECT=1: 2-stage sync + edge detect
// Clock         : clk
// Reset         : rst_n (asynchronous, active low)
// Parameters:
//   EDGE_DETECT  — 0=plain sync, 1=add rising edge detect
//   P_SHELL_MODE — 1=shell mode, all outputs tied to safe values
//******************************************************************************

module adc_sync_cell #(
    parameter EDGE_DETECT  = 0,
    parameter P_SHELL_MODE = 0
) (
    input  wire clk,
    input  wire rst_n,
    input  wire async_in,

    output wire sync_out,
    output wire rise_detect
);

    //==========================================================================
    // Single generate block — combined P_SHELL_MODE and EDGE_DETECT
    //==========================================================================
    generate
        if (P_SHELL_MODE) begin : gen_shell

            assign sync_out   = 1'b0;
            assign rise_detect = 1'b0;

        end else if (EDGE_DETECT) begin : gen_edge

            // Internal Signals
            reg sync_ff1;
            reg sync_ff2;
            reg sync_dly;

            // 2-stage synchronizer
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    sync_ff1 <= 1'b0;
                    sync_ff2 <= 1'b0;
                end else begin
                    sync_ff1 <= async_in;
                    sync_ff2 <= sync_ff1;
                end
            end

            assign sync_out = sync_ff2;

            // Rising edge detection
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    sync_dly <= 1'b0;
                end else begin
                    sync_dly <= sync_out;
                end
            end

            assign rise_detect = sync_out & (~sync_dly);

        end else begin : gen_plain

            // Internal Signals
            reg sync_ff1;
            reg sync_ff2;

            // 2-stage synchronizer, no edge detect
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    sync_ff1 <= 1'b0;
                    sync_ff2 <= 1'b0;
                end else begin
                    sync_ff1 <= async_in;
                    sync_ff2 <= sync_ff1;
                end
            end

            assign sync_out   = sync_ff2;
            assign rise_detect = 1'b0;

        end
    endgenerate

endmodule
