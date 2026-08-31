module lob_order_sram (
    input  logic        clk,
    input  logic        en,
    input  logic        we,
    input  logic [9:0]  addr,
    input  logic [31:0] wdata,
    output logic [31:0] rdata
);

`ifdef USE_HARD_SRAM

    logic [1:0] read_bank;

    wire [31:0] bank0_dout;
    wire [31:0] bank1_dout;
    wire [31:0] bank2_dout;
    wire [31:0] bank3_dout;

    wire [31:0] unused_dout1_bank0;
    wire [31:0] unused_dout1_bank1;
    wire [31:0] unused_dout1_bank2;
    wire [31:0] unused_dout1_bank3;

    always_ff @(posedge clk) begin
        if (en && !we)
            read_bank <= addr[9:8];
    end

    always_comb begin
        case (read_bank)
            2'd0: rdata = bank0_dout;
            2'd1: rdata = bank1_dout;
            2'd2: rdata = bank2_dout;
            2'd3: rdata = bank3_dout;
            default: rdata = '0;
        endcase
    end

    sky130_sram_1kbyte_1rw1r_32x256_8 bank0 (
        .clk0   (clk),
        .csb0   (!(en && addr[9:8] == 2'd0)),
        .web0   (!we),
        .wmask0 (4'b1111),
        .addr0  (addr[7:0]),
        .din0   (wdata),
        .dout0  (bank0_dout),

        .clk1   (clk),
        .csb1   (1'b1),
        .addr1  (8'b0),
        .dout1  (unused_dout1_bank0)
    );

    sky130_sram_1kbyte_1rw1r_32x256_8 bank1 (
        .clk0   (clk),
        .csb0   (!(en && addr[9:8] == 2'd1)),
        .web0   (!we),
        .wmask0 (4'b1111),
        .addr0  (addr[7:0]),
        .din0   (wdata),
        .dout0  (bank1_dout),

        .clk1   (clk),
        .csb1   (1'b1),
        .addr1  (8'b0),
        .dout1  (unused_dout1_bank1)
    );

    sky130_sram_1kbyte_1rw1r_32x256_8 bank2 (
        .clk0   (clk),
        .csb0   (!(en && addr[9:8] == 2'd2)),
        .web0   (!we),
        .wmask0 (4'b1111),
        .addr0  (addr[7:0]),
        .din0   (wdata),
        .dout0  (bank2_dout),

        .clk1   (clk),
        .csb1   (1'b1),
        .addr1  (8'b0),
        .dout1  (unused_dout1_bank2)
    );

    sky130_sram_1kbyte_1rw1r_32x256_8 bank3 (
        .clk0   (clk),
        .csb0   (!(en && addr[9:8] == 2'd3)),
        .web0   (!we),
        .wmask0 (4'b1111),
        .addr0  (addr[7:0]),
        .din0   (wdata),
        .dout0  (bank3_dout),

        .clk1   (clk),
        .csb1   (1'b1),
        .addr1  (8'b0),
        .dout1  (unused_dout1_bank3)
    );

`else

    logic [31:0] mem [0:1023];

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
