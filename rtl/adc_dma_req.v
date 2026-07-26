//*********************** Module Header ***************************************
// Module        : adc_dma_req
// Description   : DMA request controller
//                 Receives event pulses from adc_seq_fsm, gates with DMA_CTRL,
//                 produces dma_ndreq (active-low) level output. Cleared on dma_ack.
// Clock         : adc_clk
// Reset         : rst_adc_n (asynchronous, active low)
// Parameters:
//   P_SHELL_MODE — 1 = shell mode, all outputs tied to safe values
//******************************************************************************

module adc_dma_req #(
    parameter P_SHELL_MODE = 0
) (
    input  wire        adc_clk,
    input  wire        rst_adc_n,

    // Event pulses from adc_seq_fsm
    input  wire        lp_eoc_pulse,
    input  wire        lp_seq_done_pulse,
    input  wire        hp_eoc_pulse,
    input  wire        hp_seq_done_pulse,
    // overflow_event removed — now generated in PCLK in regfile. DMA on
    // OVERRUN is no longer supported (spec removed OVERRUN DMA trigger).
    // Keeping the DMA_CTRL[5] bit for SW backward-compat but it has no effect.

    // Configuration (from regfile, synchronized to ADC_CLK domain)
    input  wire        cfg_dma_en,
    input  wire [5:0]  cfg_dma_ctrl,

    // DMA handshake (dma_ndreq: active-low request)
    output wire        dma_ndreq,
    input  wire        dma_ack,

    // Status (to regfile)
    output wire        dma_busy,
    output wire        dma_done
);

    generate
        if (P_SHELL_MODE) begin : gen_shell

            assign dma_ndreq = 1'b1;  // inactive high (active-low)
            assign dma_busy = 1'b0;
            assign dma_done = 1'b0;

        end else begin : gen_active

            // Synchronize dma_ack (can be from different clock domain)
            reg dma_ack_s1;
            reg dma_ack_s2;

            // seq logic
            always @(posedge adc_clk or negedge rst_adc_n) begin
                if (!rst_adc_n) begin
                    dma_ack_s1 <= 1'b0;
                    dma_ack_s2 <= 1'b0;
                end else begin
                    dma_ack_s1 <= dma_ack;
                    dma_ack_s2 <= dma_ack_s1;
                end
            end

            // Internal DMA request flip-flop
            reg dma_req_r;

            // seq logic
            always @(posedge adc_clk or negedge rst_adc_n) begin
                if (!rst_adc_n) begin
                    dma_req_r <= 1'b0;
                end else begin
                    // Set on any enabled event
                    if (cfg_dma_en) begin
                        if ((lp_eoc_pulse     & cfg_dma_ctrl[1]) ||
                            (lp_seq_done_pulse & cfg_dma_ctrl[2]) ||
                            (hp_eoc_pulse     & cfg_dma_ctrl[3]) ||
                            (hp_seq_done_pulse & cfg_dma_ctrl[4])) begin
                            // OVERRUN (cfg_dma_ctrl[5]) no longer triggers DMA —
                            // overflow is detected in PCLK and not forwarded here.
                            dma_req_r <= 1'b1;
                        end
                    end
                    // Clear on acknowledge (synchronized)
                    if (dma_ack_s2) begin
                        dma_req_r <= 1'b0;
                    end
                end
            end

            assign dma_ndreq = ~dma_req_r;  // active-low
            assign dma_busy = dma_req_r;
            assign dma_done = dma_ack_s2;

        end
    endgenerate

endmodule
