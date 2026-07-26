//*********************** Module Header ***************************************
// Module        : adc_trig_sync
// Description   : MCTM trigger synchronization with rising edge detection
//                 and trigger source selection for LP/HP priority paths.
//                 Each mctm_trig channel is synchronized via adc_sync_cell
//                 with edge detection. The selected source is gated by the
//                 corresponding enable and routed to the priority output.
// Clock         : clk (ADC_CLK)
// Reset         : rst_n (asynchronous, active low)
// Parameters:
//   P_SHELL_MODE — 1=shell mode, all outputs tied to safe values
//
// Trigger source encoding (TRG_SEL[3:0]):
//   0000=mctm0  0001=mctm1  0010=mctm2  0011=mctm3
//   0100=mctm4  0101=mctm5  0110=mctm3|4  0111=ecc
//   1000=tue    1001~1111=reserved (no output)
//******************************************************************************

module adc_trig_sync #(
    parameter P_SHELL_MODE = 0
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [5:0]  mctm_trig,
    input  wire [3:0]  lp_trg_sel,
    input  wire [3:0]  hp_trg_sel,
    input  wire        lp_mctm_en,
    input  wire        hp_mctm_en,
    input  wire        lp_sw_trg_en,
    input  wire        hp_sw_trg_en,
    input  wire        lp_sw_trig_raw,
    input  wire        hp_sw_trig_raw,

    output wire        lp_trig_pulse,
    output wire        hp_trig_pulse
);

    //==========================================================================
    // Shell Mode
    //==========================================================================
    generate
        if (P_SHELL_MODE) begin : gen_shell

            assign lp_trig_pulse = 1'b0;
            assign hp_trig_pulse = 1'b0;

        end else begin : gen_active

            //==========================================================================
            // Internal Signals
            //==========================================================================
            wire [5:0] mctm_edge;

            //==========================================================================
            // MCTM Channel Synchronization
            //==========================================================================
            // Each channel is synchronized and edge-detected individually.
            // Unused edge outputs are left open.

            adc_sync_cell #(.EDGE_DETECT(1)) u_sync_mctm0
            (
                .clk        (clk             ),
                .rst_n      (rst_n           ),
                .async_in   (mctm_trig[0]    ),
                .sync_out   (                ),
                .rise_detect(mctm_edge[0]    )
            );

            adc_sync_cell #(.EDGE_DETECT(1)) u_sync_mctm1
            (
                .clk        (clk             ),
                .rst_n      (rst_n           ),
                .async_in   (mctm_trig[1]    ),
                .sync_out   (                ),
                .rise_detect(mctm_edge[1]    )
            );

            adc_sync_cell #(.EDGE_DETECT(1)) u_sync_mctm2
            (
                .clk        (clk             ),
                .rst_n      (rst_n           ),
                .async_in   (mctm_trig[2]    ),
                .sync_out   (                ),
                .rise_detect(mctm_edge[2]    )
            );

            adc_sync_cell #(.EDGE_DETECT(1)) u_sync_mctm3
            (
                .clk        (clk             ),
                .rst_n      (rst_n           ),
                .async_in   (mctm_trig[3]    ),
                .sync_out   (                ),
                .rise_detect(mctm_edge[3]    )
            );

            adc_sync_cell #(.EDGE_DETECT(1)) u_sync_mctm4
            (
                .clk        (clk             ),
                .rst_n      (rst_n           ),
                .async_in   (mctm_trig[4]    ),
                .sync_out   (                ),
                .rise_detect(mctm_edge[4]    )
            );

            adc_sync_cell #(.EDGE_DETECT(1)) u_sync_mctm5
            (
                .clk        (clk             ),
                .rst_n      (rst_n           ),
                .async_in   (mctm_trig[5]    ),
                .sync_out   (                ),
                .rise_detect(mctm_edge[5]    )
            );

            //==========================================================================
            // Trigger Source Selection
            //==========================================================================
            // combo logic
            // Derived trigger: mctm3|4 = edge[3] OR edge[4]
            wire mctm_3or4_edge;
            assign mctm_3or4_edge = mctm_edge[3] | mctm_edge[4];

            // Source mux for low-priority trigger
            reg lp_src_pulse;
            always @(*) begin
                case (lp_trg_sel)
                    4'h0 : lp_src_pulse = mctm_edge[0];
                    4'h1 : lp_src_pulse = mctm_edge[1];
                    4'h2 : lp_src_pulse = mctm_edge[2];
                    4'h3 : lp_src_pulse = mctm_edge[3];
                    4'h4 : lp_src_pulse = mctm_edge[4];
                    4'h5 : lp_src_pulse = mctm_edge[5];
                    4'h6 : lp_src_pulse = mctm_3or4_edge;
                    4'h7 : lp_src_pulse = mctm_edge[0];   // ecc — mapped to mctm0 for now
                    4'h8 : lp_src_pulse = mctm_edge[1];   // tue — mapped to mctm1 for now
                    default : lp_src_pulse = 1'b0;
                endcase
            end

            // Source mux for high-priority trigger
            reg hp_src_pulse;
            always @(*) begin
                case (hp_trg_sel)
                    4'h0 : hp_src_pulse = mctm_edge[0];
                    4'h1 : hp_src_pulse = mctm_edge[1];
                    4'h2 : hp_src_pulse = mctm_edge[2];
                    4'h3 : hp_src_pulse = mctm_edge[3];
                    4'h4 : hp_src_pulse = mctm_edge[4];
                    4'h5 : hp_src_pulse = mctm_edge[5];
                    4'h6 : hp_src_pulse = mctm_3or4_edge;
                    4'h7 : hp_src_pulse = mctm_edge[0];   // ecc — mapped to mctm0 for now
                    4'h8 : hp_src_pulse = mctm_edge[1];   // tue — mapped to mctm1 for now
                    default : hp_src_pulse = 1'b0;
                endcase
            end

            // Software trigger — 2-stage CDC sync (PCLK domain pulse → ADC_CLK)
            //   lp_sw_trig_raw is a 1-cycle PCLK pulse. Without 2-stage sync,
            //   ADC_CLK may miss it (PCLK 20ns pulse vs ADC_CLK 40ns period).
            //   Sync first, then edge-detect on the synced signal.
            reg lp_sw_sync1, lp_sw_sync2;
            reg hp_sw_sync1, hp_sw_sync2;
            reg lp_sw_dly;
            reg hp_sw_dly;

            // seq logic: 2-stage CDC sync of PCLK-domain SW trigger
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    lp_sw_sync1 <= 1'b0;
                    lp_sw_sync2 <= 1'b0;
                    hp_sw_sync1 <= 1'b0;
                    hp_sw_sync2 <= 1'b0;
                    lp_sw_dly   <= 1'b0;
                    hp_sw_dly   <= 1'b0;
                end else begin
                    // 2-stage sync: PCLK pulse → ADC_CLK domain
                    lp_sw_sync1 <= lp_sw_trig_raw;
                    lp_sw_sync2 <= lp_sw_sync1;
                    hp_sw_sync1 <= hp_sw_trig_raw;
                    hp_sw_sync2 <= hp_sw_sync1;
                    // Edge detect on synced signal
                    lp_sw_dly   <= lp_sw_sync2;
                    hp_sw_dly   <= hp_sw_sync2;
                end
            end

            wire lp_sw_pulse = lp_sw_sync2 & (~lp_sw_dly);
            wire hp_sw_pulse = hp_sw_sync2 & (~hp_sw_dly);

            // Gate with enable and output — OR with SW trigger path
            assign lp_trig_pulse = (lp_sw_trg_en & lp_sw_pulse) | (lp_mctm_en & lp_src_pulse);
            assign hp_trig_pulse = (hp_sw_trg_en & hp_sw_pulse) | (hp_mctm_en & hp_src_pulse);

        end
    endgenerate

endmodule
