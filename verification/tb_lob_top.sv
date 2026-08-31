`timescale 1ns/1ps

module tb_lob_top;

    parameter int ORDER_ID_WIDTH = 10;
    parameter int PRICE_WIDTH = 8;
    parameter int QUANTITY_WIDTH = 16;
    parameter int FIFO_DEPTH = 16;
    parameter int MESSAGE_WIDTH =
        2 + ORDER_ID_WIDTH + 1 + PRICE_WIDTH + QUANTITY_WIDTH;
    parameter int NUM_ORDERS = (1 << ORDER_ID_WIDTH);
    parameter int NUM_PRICE_LEVELS = (1 << PRICE_WIDTH);

    logic arst_n;

    logic feed_clk;
    logic feed_valid;
    logic [1:0] feed_opcode;
    logic [ORDER_ID_WIDTH-1:0] feed_order_id;
    logic feed_side;
    logic [PRICE_WIDTH-1:0] feed_price;
    logic [QUANTITY_WIDTH-1:0] feed_quantity;
    logic feed_ready;

    logic book_clk;
    logic book_ready;
    logic book_update_valid;
    logic [PRICE_WIDTH-1:0] best_bid;
    logic [PRICE_WIDTH-1:0] best_ask;
    logic best_bid_valid;
    logic best_ask_valid;

    logic [MESSAGE_WIDTH-1:0] expected_fifo[$];
    logic [MESSAGE_WIDTH-1:0] processing_queue[$];

    logic ref_order_valid [0:NUM_ORDERS-1];
    logic ref_order_side [0:NUM_ORDERS-1];
    logic [PRICE_WIDTH-1:0] ref_order_price [0:NUM_ORDERS-1];
    logic [QUANTITY_WIDTH-1:0] ref_order_quantity [0:NUM_ORDERS-1];

    integer ref_bid_quantity [0:NUM_PRICE_LEVELS-1];
    integer ref_ask_quantity [0:NUM_PRICE_LEVELS-1];

    logic source_order_valid [0:NUM_ORDERS-1];
    logic [QUANTITY_WIDTH-1:0] source_order_quantity [0:NUM_ORDERS-1];

    integer error_count;
    integer transaction_count;
    integer i;

    lob_top #(
        .ORDER_ID_WIDTH (ORDER_ID_WIDTH),
        .PRICE_WIDTH    (PRICE_WIDTH),
        .QUANTITY_WIDTH (QUANTITY_WIDTH),
        .FIFO_DEPTH     (FIFO_DEPTH)
    ) dut (
        .arst_n            (arst_n),

        .feed_clk          (feed_clk),
        .feed_valid        (feed_valid),
        .feed_opcode       (feed_opcode),
        .feed_order_id     (feed_order_id),
        .feed_side         (feed_side),
        .feed_price        (feed_price),
        .feed_quantity     (feed_quantity),
        .feed_ready        (feed_ready),

        .book_clk          (book_clk),
        .book_ready        (book_ready),
        .book_update_valid (book_update_valid),
        .best_bid          (best_bid),
        .best_ask          (best_ask),
        .best_bid_valid    (best_bid_valid),
        .best_ask_valid    (best_ask_valid)
    );

    async_fifo_sva #(
        .ADDR_WIDTH ($clog2(FIFO_DEPTH))
    ) fifo_assertions (
        .wr_clk   (feed_clk),
        .wr_rst_n (dut.feed_rst_n),
        .wr_en    (dut.fifo.wr_en),
        .full     (dut.fifo.full),
        .wr_bin   (dut.fifo.wr_bin),
        .wr_gray  (dut.fifo.wr_gray),

        .rd_clk   (book_clk),
        .rd_rst_n (dut.book_rst_n),
        .rd_en    (dut.fifo.rd_en),
        .empty    (dut.fifo.empty),
        .rd_valid (dut.fifo.rd_valid),
        .rd_bin   (dut.fifo.rd_bin),
        .rd_gray  (dut.fifo.rd_gray)
    );

    lob_engine_sva engine_assertions (
        .clk          (book_clk),
        .rst_n        (dut.book_rst_n),
        .msg_valid    (dut.fifo_rd_valid),
        .ready        (book_ready),
        .update_valid (book_update_valid)
    );

    initial begin
        feed_clk = 1'b0;
        forever #4 feed_clk = ~feed_clk;
    end

    initial begin
        book_clk = 1'b0;
        forever #2.5 book_clk = ~book_clk;
    end

    function automatic [MESSAGE_WIDTH-1:0] pack_message(
        input logic [1:0] opcode,
        input logic [ORDER_ID_WIDTH-1:0] order_id,
        input logic side,
        input logic [PRICE_WIDTH-1:0] price,
        input logic [QUANTITY_WIDTH-1:0] quantity
    );
        pack_message = {opcode, order_id, side, price, quantity};
    endfunction

    task automatic drive_message(
        input logic [1:0] opcode,
        input logic [ORDER_ID_WIDTH-1:0] order_id,
        input logic side,
        input logic [PRICE_WIDTH-1:0] price,
        input logic [QUANTITY_WIDTH-1:0] quantity
    );
        begin
            @(negedge feed_clk);

            while (!feed_ready)
                @(negedge feed_clk);

            feed_opcode = opcode;
            feed_order_id = order_id;
            feed_side = side;
            feed_price = price;
            feed_quantity = quantity;
            feed_valid = 1'b1;

            @(negedge feed_clk);
            feed_valid = 1'b0;

            expected_fifo.push_back(
                pack_message(opcode, order_id, side, price, quantity)
            );

            transaction_count = transaction_count + 1;
        end
    endtask

    task automatic add_order(
        input int order_id,
        input int side,
        input int price,
        input int quantity
    );
        begin
            drive_message(
                2'b00,
                order_id[ORDER_ID_WIDTH-1:0],
                side[0],
                price[PRICE_WIDTH-1:0],
                quantity[QUANTITY_WIDTH-1:0]
            );

            source_order_valid[order_id] = 1'b1;
            source_order_quantity[order_id] = quantity;
        end
    endtask

    task automatic reduce_order(
        input int opcode,
        input int order_id,
        input int quantity
    );
        integer remaining;
        begin
            drive_message(
                opcode[1:0],
                order_id[ORDER_ID_WIDTH-1:0],
                1'b0,
                '0,
                quantity[QUANTITY_WIDTH-1:0]
            );

            if (quantity >= source_order_quantity[order_id]) begin
                source_order_valid[order_id] = 1'b0;
                source_order_quantity[order_id] = '0;
            end else begin
                remaining = source_order_quantity[order_id] - quantity;
                source_order_quantity[order_id] = remaining;
            end
        end
    endtask

    task automatic update_reference(
        input logic [1:0] opcode,
        input logic [ORDER_ID_WIDTH-1:0] order_id,
        input logic side,
        input logic [PRICE_WIDTH-1:0] price,
        input logic [QUANTITY_WIDTH-1:0] quantity
    );
        integer reduction;
        begin
            case (opcode)
                2'b00: begin
                    if (!ref_order_valid[order_id] && quantity != 0) begin
                        ref_order_valid[order_id] = 1'b1;
                        ref_order_side[order_id] = side;
                        ref_order_price[order_id] = price;
                        ref_order_quantity[order_id] = quantity;

                        if (side == 1'b0)
                            ref_bid_quantity[price] =
                                ref_bid_quantity[price] + quantity;
                        else
                            ref_ask_quantity[price] =
                                ref_ask_quantity[price] + quantity;
                    end
                end

                2'b01,
                2'b10: begin
                    if (ref_order_valid[order_id]) begin
                        if (quantity >= ref_order_quantity[order_id])
                            reduction = ref_order_quantity[order_id];
                        else
                            reduction = quantity;

                        if (ref_order_side[order_id] == 1'b0)
                            ref_bid_quantity[ref_order_price[order_id]] =
                                ref_bid_quantity[ref_order_price[order_id]] - reduction;
                        else
                            ref_ask_quantity[ref_order_price[order_id]] =
                                ref_ask_quantity[ref_order_price[order_id]] - reduction;

                        if (reduction == ref_order_quantity[order_id]) begin
                            ref_order_valid[order_id] = 1'b0;
                            ref_order_quantity[order_id] = '0;
                        end else begin
                            ref_order_quantity[order_id] =
                                ref_order_quantity[order_id] - reduction;
                        end
                    end
                end

                default: begin
                end
            endcase
        end
    endtask

    task automatic check_top_of_book;
        integer expected_bid;
        integer expected_ask;
        bit expected_bid_valid;
        bit expected_ask_valid;
        integer p;
        begin
            expected_bid = 0;
            expected_ask = 0;
            expected_bid_valid = 1'b0;
            expected_ask_valid = 1'b0;

            for (p = 0; p < NUM_PRICE_LEVELS; p = p + 1) begin
                if (ref_bid_quantity[p] != 0) begin
                    expected_bid = p;
                    expected_bid_valid = 1'b1;
                end
            end

            for (p = NUM_PRICE_LEVELS - 1; p >= 0; p = p - 1) begin
                if (ref_ask_quantity[p] != 0) begin
                    expected_ask = p;
                    expected_ask_valid = 1'b1;
                end
            end

            if (best_bid_valid !== expected_bid_valid) begin
                $error("best_bid_valid mismatch. RTL=%0b REF=%0b",
                       best_bid_valid, expected_bid_valid);
                error_count = error_count + 1;
            end else if (expected_bid_valid &&
                         best_bid !== expected_bid[PRICE_WIDTH-1:0]) begin
                $error("best_bid mismatch. RTL=%0d REF=%0d",
                       best_bid, expected_bid);
                error_count = error_count + 1;
            end

            if (best_ask_valid !== expected_ask_valid) begin
                $error("best_ask_valid mismatch. RTL=%0b REF=%0b",
                       best_ask_valid, expected_ask_valid);
                error_count = error_count + 1;
            end else if (expected_ask_valid &&
                         best_ask !== expected_ask[PRICE_WIDTH-1:0]) begin
                $error("best_ask mismatch. RTL=%0d REF=%0d",
                       best_ask, expected_ask);
                error_count = error_count + 1;
            end
        end
    endtask

    always @(posedge book_clk) begin
        logic [MESSAGE_WIDTH-1:0] actual_message;
        logic [MESSAGE_WIDTH-1:0] expected_message;
        logic accepted_by_engine;

        accepted_by_engine =
            dut.book_rst_n && dut.fifo_rd_valid && book_ready;

        if (dut.book_rst_n && dut.fifo_rd_valid) begin
            actual_message = {
                dut.engine_opcode,
                dut.engine_order_id,
                dut.engine_side,
                dut.engine_price,
                dut.engine_quantity
            };

            if (expected_fifo.size() == 0) begin
                $error("Engine received a message that was never written");
                error_count = error_count + 1;
            end else begin
                expected_message = expected_fifo.pop_front();

                if (actual_message !== expected_message) begin
                    $error("FIFO ordering/data mismatch");
                    error_count = error_count + 1;
                end
            end

            if (accepted_by_engine)
                processing_queue.push_back(actual_message);
        end

        #1;

        if (dut.book_rst_n && book_update_valid) begin
            if (processing_queue.size() == 0) begin
                $error("Engine completed with no pending reference message");
                error_count = error_count + 1;
            end else begin
                expected_message = processing_queue.pop_front();

                update_reference(
                    expected_message[MESSAGE_WIDTH-1 -: 2],
                    expected_message[MESSAGE_WIDTH-3 -: ORDER_ID_WIDTH],
                    expected_message[QUANTITY_WIDTH + PRICE_WIDTH],
                    expected_message[QUANTITY_WIDTH +: PRICE_WIDTH],
                    expected_message[QUANTITY_WIDTH-1:0]
                );

                check_top_of_book();
            end
        end
    end

    initial begin
        $dumpfile("lob_top.vcd");
        $dumpvars(0, tb_lob_top);

        error_count = 0;
        transaction_count = 0;

        feed_valid = 1'b0;
        feed_opcode = '0;
        feed_order_id = '0;
        feed_side = 1'b0;
        feed_price = '0;
        feed_quantity = '0;

        for (i = 0; i < NUM_ORDERS; i = i + 1) begin
            ref_order_valid[i] = 1'b0;
            ref_order_side[i] = 1'b0;
            ref_order_price[i] = '0;
            ref_order_quantity[i] = '0;
            source_order_valid[i] = 1'b0;
            source_order_quantity[i] = '0;
        end

        for (i = 0; i < NUM_PRICE_LEVELS; i = i + 1) begin
            ref_bid_quantity[i] = 0;
            ref_ask_quantity[i] = 0;
        end

        arst_n = 1'b0;
        #30;
        arst_n = 1'b1;

        wait (book_ready);
        repeat (4) @(posedge book_clk);

        add_order(1, 0, 100, 50);
        add_order(2, 0, 105, 30);
        add_order(3, 1, 110, 40);
        add_order(4, 1, 108, 25);
        reduce_order(2'b01, 2, 10);
        reduce_order(2'b10, 4, 25);

        for (i = 0; i < 500; i = i + 1) begin
            integer choice;
            integer id;
            integer side;
            integer price;
            integer quantity;
            integer attempts;

            choice = $urandom_range(0, 99);

            if (choice < 60) begin
                attempts = 0;
                id = $urandom_range(0, NUM_ORDERS - 1);

                while (source_order_valid[id] && attempts < NUM_ORDERS) begin
                    id = (id + 1) % NUM_ORDERS;
                    attempts = attempts + 1;
                end

                if (!source_order_valid[id]) begin
                    side = $urandom_range(0, 1);
                    price = $urandom_range(1, NUM_PRICE_LEVELS - 2);
                    quantity = $urandom_range(1, 500);
                    add_order(id, side, price, quantity);
                end
            end else begin
                attempts = 0;
                id = $urandom_range(0, NUM_ORDERS - 1);

                while (!source_order_valid[id] && attempts < NUM_ORDERS) begin
                    id = (id + 1) % NUM_ORDERS;
                    attempts = attempts + 1;
                end

                if (source_order_valid[id]) begin
                    quantity = $urandom_range(
                        1,
                        source_order_quantity[id] + 20
                    );

                    if (choice < 80)
                        reduce_order(2'b01, id, quantity);
                    else
                        reduce_order(2'b10, id, quantity);
                end
            end
        end

        wait (expected_fifo.size() == 0);
        wait (processing_queue.size() == 0);
        wait (book_ready);
        repeat (10) @(posedge book_clk);

        if (error_count == 0) begin
            $display("");
            $display("========================================");
            $display("PASS: %0d transactions completed", transaction_count);
            $display("========================================");
            $display("");
        end else begin
            $fatal(1, "FAIL: %0d errors detected", error_count);
        end

        $finish;
    end

endmodule
