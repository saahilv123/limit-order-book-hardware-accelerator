module async_fifo #(
    parameter int DATA_WIDTH = 37,
    parameter int DEPTH = 16,
    parameter int ADDR_WIDTH = $clog2(DEPTH)
)(
    input  logic                  wr_clk,
    input  logic                  wr_rst_n,
    input  logic                  wr_en,
    input  logic [DATA_WIDTH-1:0] wr_data,
    output logic                  full,

    input  logic                  rd_clk,
    input  logic                  rd_rst_n,
    input  logic                  rd_en,
    output logic [DATA_WIDTH-1:0] rd_data,
    output logic                  rd_valid,
    output logic                  empty
);

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    logic [ADDR_WIDTH:0] wr_bin;
    logic [ADDR_WIDTH:0] wr_bin_next;
    logic [ADDR_WIDTH:0] wr_gray;
    logic [ADDR_WIDTH:0] wr_gray_next;

    logic [ADDR_WIDTH:0] rd_bin;
    logic [ADDR_WIDTH:0] rd_bin_next;
    logic [ADDR_WIDTH:0] rd_gray;
    logic [ADDR_WIDTH:0] rd_gray_next;

    logic [ADDR_WIDTH:0] rd_gray_sync1;
    logic [ADDR_WIDTH:0] rd_gray_sync2;
    logic [ADDR_WIDTH:0] wr_gray_sync1;
    logic [ADDR_WIDTH:0] wr_gray_sync2;

    logic full_next;
    logic empty_next;

    assign wr_bin_next =
        wr_bin + ((wr_en && !full) ? 1'b1 : 1'b0);

    assign wr_gray_next =
        (wr_bin_next >> 1) ^ wr_bin_next;

    assign rd_bin_next =
        rd_bin + ((rd_en && !empty) ? 1'b1 : 1'b0);

    assign rd_gray_next =
        (rd_bin_next >> 1) ^ rd_bin_next;

    // A full FIFO has the same lower Gray bits as the synchronized read pointer
    // with the top two Gray bits inverted after wraparound
    assign full_next =
        (wr_gray_next ==
        {~rd_gray_sync2[ADDR_WIDTH:ADDR_WIDTH-1],
          rd_gray_sync2[ADDR_WIDTH-2:0]});

    assign empty_next =
        (rd_gray_next == wr_gray_sync2);

    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_bin  <= '0;
            wr_gray <= '0;
            full    <= 1'b0;
        end else begin
            if (wr_en && !full)
                mem[wr_bin[ADDR_WIDTH-1:0]] <= wr_data;

            wr_bin  <= wr_bin_next;
            wr_gray <= wr_gray_next;
            full    <= full_next;
        end
    end

    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_bin   <= '0;
            rd_gray  <= '0;
            rd_data  <= '0;
            rd_valid <= 1'b0;
            empty    <= 1'b1;
        end else begin
            rd_valid <= rd_en && !empty;

            if (rd_en && !empty)
                rd_data <= mem[rd_bin[ADDR_WIDTH-1:0]];

            rd_bin  <= rd_bin_next;
            rd_gray <= rd_gray_next;
            empty   <= empty_next;
        end
    end

    // Read pointer crosses into the write clock domain
    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            rd_gray_sync1 <= '0;
            rd_gray_sync2 <= '0;
        end else begin
            rd_gray_sync1 <= rd_gray;
            rd_gray_sync2 <= rd_gray_sync1;
        end
    end

    // Write pointer crosses into the read clock domain
    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            wr_gray_sync1 <= '0;
            wr_gray_sync2 <= '0;
        end else begin
            wr_gray_sync1 <= wr_gray;
            wr_gray_sync2 <= wr_gray_sync1;
        end
    end

endmodule
