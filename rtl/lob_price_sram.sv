module lob_price_sram (
    input  logic        clk,
    input  logic        en,
    input  logic        we,
    input  logic [7:0]  addr,
    input  logic [31:0] wdata,
    output logic [31:0] rdata
);

`ifdef USE_HARD_SRAM

    wire [31:0] macro_dout;
    wire [31:0] unused_dout1;

    assign rdata = macro_dout;

    sky130_sram_1kbyte_1rw1r_32x256_8 memory (
        .clk0   (clk),
        .csb0   (!en),
        .web0   (!we),
        .wmask0 (4'b1111),
        .addr0  (addr),
        .din0   (wdata),
        .dout0  (macro_dout),

        .clk1   (clk),
        .csb1   (1'b1),
        .addr1  (8'b0),
        .dout1  (unused_dout1)
    );

`else

    logic [31:0] mem [0:255];

    always_ff @(posedge clk) begin
        if (en) begin
            if (we)
                mem[addr] <= wdata;
            else
                rdata <= mem[addr];
        end
    end

`endif

endmodule
