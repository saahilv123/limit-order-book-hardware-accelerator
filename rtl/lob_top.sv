module lob_top #(
    parameter int ORDER_ID_WIDTH = 10,
    parameter int PRICE_WIDTH = 8,
    parameter int QUANTITY_WIDTH = 16,
    parameter int FIFO_DEPTH = 16,
    parameter int MESSAGE_WIDTH =
        2 + ORDER_ID_WIDTH + 1 + PRICE_WIDTH + QUANTITY_WIDTH
)(
    input  logic                       arst_n,

    input  logic                       feed_clk,
    input  logic                       feed_valid,
    input  logic [1:0]                 feed_opcode,
    input  logic [ORDER_ID_WIDTH-1:0]  feed_order_id,
    input  logic                       feed_side,
    input  logic [PRICE_WIDTH-1:0]     feed_price,
    input  logic [QUANTITY_WIDTH-1:0]  feed_quantity,
    output logic                       feed_ready,

    input  logic                       book_clk,
    output logic                       book_ready,
    output logic                       book_update_valid,
    output logic [PRICE_WIDTH-1:0]     best_bid,
    output logic [PRICE_WIDTH-1:0]     best_ask,
    output logic                       best_bid_valid,
    output logic                       best_ask_valid
);

    logic feed_rst_n;
    logic book_rst_n;

    logic [MESSAGE_WIDTH-1:0] fifo_wr_data;
    logic [MESSAGE_WIDTH-1:0] fifo_rd_data;
    logic fifo_full;
    logic fifo_empty;
    logic fifo_rd_en;
    logic fifo_rd_valid;
    logic fifo_read_pending;

    logic [1:0] engine_opcode;
    logic [ORDER_ID_WIDTH-1:0] engine_order_id;
    logic engine_side;
    logic [PRICE_WIDTH-1:0] engine_price;
    logic [QUANTITY_WIDTH-1:0] engine_quantity;

    reset_sync feed_reset_sync (
        .clk    (feed_clk),
        .arst_n (arst_n),
        .rst_n  (feed_rst_n)
    );

    reset_sync book_reset_sync (
        .clk    (book_clk),
        .arst_n (arst_n),
        .rst_n  (book_rst_n)
    );

    assign fifo_wr_data = {
        feed_opcode,
        feed_order_id,
        feed_side,
        feed_price,
        feed_quantity
    };

    assign feed_ready = feed_rst_n && !fifo_full;

    async_fifo #(
        .DATA_WIDTH (MESSAGE_WIDTH),
        .DEPTH      (FIFO_DEPTH)
    ) fifo (
        .wr_clk   (feed_clk),
        .wr_rst_n (feed_rst_n),
        .wr_en    (feed_valid && feed_ready),
        .wr_data  (fifo_wr_data),
        .full     (fifo_full),

        .rd_clk   (book_clk),
        .rd_rst_n (book_rst_n),
        .rd_en    (fifo_rd_en),
        .rd_data  (fifo_rd_data),
        .rd_valid (fifo_rd_valid),
        .empty    (fifo_empty)
    );

    assign {
        engine_opcode,
        engine_order_id,
        engine_side,
        engine_price,
        engine_quantity
    } = fifo_rd_data;

    // The FIFO has a registered read, keep at most one read outstanding so
    // a second message cannot arrive while the pipelined engine is busy
    assign fifo_rd_en =
        book_ready && !fifo_empty && !fifo_read_pending;

    always_ff @(posedge book_clk or negedge book_rst_n) begin
        if (!book_rst_n) begin
            fifo_read_pending <= 1'b0;
        end else begin
            if (fifo_rd_en)
                fifo_read_pending <= 1'b1;

            if (fifo_rd_valid)
                fifo_read_pending <= 1'b0;
        end
    end

    lob_engine #(
        .ORDER_ID_WIDTH (ORDER_ID_WIDTH),
        .PRICE_WIDTH    (PRICE_WIDTH),
        .QUANTITY_WIDTH (QUANTITY_WIDTH)
    ) engine (
        .clk            (book_clk),
        .rst_n          (book_rst_n),

        .msg_valid      (fifo_rd_valid),
        .msg_opcode     (engine_opcode),
        .msg_order_id   (engine_order_id),
        .msg_side       (engine_side),
        .msg_price      (engine_price),
        .msg_quantity   (engine_quantity),

        .ready          (book_ready),
        .update_valid   (book_update_valid),
        .best_bid       (best_bid),
        .best_ask       (best_ask),
        .best_bid_valid (best_bid_valid),
        .best_ask_valid (best_ask_valid)
    );

endmodule
