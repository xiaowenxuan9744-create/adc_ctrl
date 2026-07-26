//*********************** Module Header ***************************************
// Module    : adc_apb_if
// Description  : APB 32-bit slave interface, zero wait-state
//                Address decoding is handled by regfile; this module only
//                performs protocol parsing and address forwarding.
// Clock     : PCLK
// Reset     : PRESETn (synchronous, active low)
// Parameters:
//   P_SHELL_MODE — 1 = shell mode, all outputs tied to safe values
//******************************************************************************

module adc_apb_if #(
    parameter P_SHELL_MODE = 0
) (
    // APB interface
    input  wire              PCLK,
    input  wire              PRESETn,
    input  wire [15:0]       PADDR,
    input  wire              PWRITE,
    input  wire              PSEL,
    input  wire              PENABLE,
    input  wire [31:0]       PWDATA,
    output wire [31:0]       PRDATA,
    output wire              PREADY,
    output wire              PSLVERR,

    // Internal: to regfile (combo)
    output wire              reg_wr_en,
    output wire              reg_rd_en,
    output wire [15:0]       reg_addr,
    output wire [31:0]       wr_data,

    // Internal: from regfile (combo read data)
    input  wire [31:0]       rd_data
);

    //==========================================================================
    // Shell Mode
    //==========================================================================
    generate
        if (P_SHELL_MODE) begin : gen_shell

            assign PREADY    = 1'b1;
            assign PSLVERR   = 1'b0;
            assign PRDATA    = {32{1'b0}};
            assign reg_wr_en = 1'b0;
            assign reg_rd_en = 1'b0;
            assign reg_addr  = {16{1'b0}};
            assign wr_data   = {32{1'b0}};

        end else begin : gen_active

            //==========================================================================
            // APB Protocol Decode
            //==========================================================================
            // Zero wait-state slave — always ready, no error
            assign PREADY  = 1'b1;
            assign PSLVERR = 1'b0;

            // Write strobe: valid APB write cycle
            assign reg_wr_en = PSEL & PENABLE & PWRITE;

            // Read strobe: valid APB read cycle
            assign reg_rd_en = PSEL & PENABLE & (~PWRITE);

            // Forward address and write data to regfile
            assign reg_addr = PADDR;
            assign wr_data  = PWDATA;

            // PRDATA presents rd_data from regfile during valid read cycles
            assign PRDATA = reg_rd_en ? rd_data : 32'h0;

        end
    endgenerate

endmodule
