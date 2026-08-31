`timescale 1ns/1ps

module tb_async_fifo;

    parameter int DATA_WIDTH = 32;
    parameter int DEPTH = 16;

    logic wr_clk;
    logic wr_rst_n;
    logic wr_en;
    logic [DATA_WIDTH-1:0] wr_data;
    logic full;

    logic rd_clk;
    logic rd_rst_n;
    logic rd_en;
    logic [DATA_WIDTH-1:0] rd_data;
    logic rd_valid;
    logic empty;

    logic [DATA_WIDTH-1:0] expected_queue[$];

    integer next_value;
    integer writes_accepted;
    integer reads_checked;
    integer error_count;
    integer saw_full;
    integer saw_empty_after_traffic;

    async_fifo #(
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (DEPTH)
    ) dut (
        .wr_clk   (wr_clk),
        .wr_rst_n (wr_rst_n),
        .wr_en    (wr_en),
        .wr_data  (wr_data),
        .full     (full),

        .rd_clk   (rd_clk),
        .rd_rst_n (rd_rst_n),
        .rd_en    (rd_en),
        .rd_data  (rd_data),
        .rd_valid (rd_valid),
        .empty    (empty)
    );

    async_fifo_sva #(
        .ADDR_WIDTH ($clog2(DEPTH))
    ) fifo_assertions (
        .wr_clk   (wr_clk),
        .wr_rst_n (wr_rst_n),
        .wr_en    (wr_en),
        .full     (full),
        .wr_bin   (dut.wr_bin),
        .wr_gray  (dut.wr_gray),

        .rd_clk   (rd_clk),
        .rd_rst_n (rd_rst_n),
        .rd_en    (rd_en),
        .empty    (empty),
        .rd_valid (rd_valid),
        .rd_bin   (dut.rd_bin),
        .rd_gray  (dut.rd_gray)
    );

    initial begin
        wr_clk = 1'b0;
        forever #2 wr_clk = ~wr_clk;
    end

    initial begin
        rd_clk = 1'b0;
        #1;
        forever #5 rd_clk = ~rd_clk;
    end

    always @(posedge wr_clk) begin
        if (wr_rst_n) begin
            if (full)
                saw_full = 1;

            if (wr_en && !full) begin
                expected_queue.push_back(wr_data);
                writes_accepted = writes_accepted + 1;
            end
        end
    end

    always @(posedge rd_clk) begin
        logic [DATA_WIDTH-1:0] expected_value;

        if (rd_rst_n && rd_valid) begin
            if (expected_queue.size() == 0) begin
                $error("FIFO produced data with an empty scoreboard queue");
                error_count = error_count + 1;
            end else begin
                expected_value = expected_queue.pop_front();

                if (rd_data !== expected_value) begin
                    $error(
                        "FIFO data mismatch. RTL=0x%08x REF=0x%08x",
                        rd_data,
                        expected_value
                    );
                    error_count = error_count + 1;
                end
            end

            reads_checked = reads_checked + 1;
        end

        if (rd_rst_n &&
            writes_accepted >= 1000 &&
            expected_queue.size() == 0 &&
            empty)
            saw_empty_after_traffic = 1;
    end

    initial begin
        wr_rst_n = 1'b0;
        rd_rst_n = 1'b0;
        wr_en = 1'b0;
        rd_en = 1'b0;
        wr_data = '0;

        next_value = 1;
        writes_accepted = 0;
        reads_checked = 0;
        error_count = 0;
        saw_full = 0;
        saw_empty_after_traffic = 0;

        #30;
        wr_rst_n = 1'b1;
        rd_rst_n = 1'b1;

        while (writes_accepted < 1000) begin
            @(negedge wr_clk);

            wr_en = 1'b1;
            wr_data = next_value[DATA_WIDTH-1:0];

            if (!full)
                next_value = next_value + 1;
        end

        @(negedge wr_clk);
        wr_en = 1'b0;

        wait (writes_accepted >= 4);
    end

    initial begin
        wait (rd_rst_n);
        repeat (4) @(negedge rd_clk);

        while (!saw_empty_after_traffic) begin
            @(negedge rd_clk);
            rd_en = 1'b1;
        end

        @(negedge rd_clk);
        rd_en = 1'b0;

        repeat (4) @(posedge rd_clk);

        if (!saw_full) begin
            $error("FIFO stress test never reached full");
            error_count = error_count + 1;
        end

        if (reads_checked != writes_accepted) begin
            $error(
                "Accepted write/read count mismatch. writes=%0d reads=%0d",
                writes_accepted,
                reads_checked
            );
            error_count = error_count + 1;
        end

        if (error_count == 0) begin
            $display("");
            $display("========================================");
            $display("PASS: async FIFO stress test");
            $display("accepted writes : %0d", writes_accepted);
            $display("checked reads   : %0d", reads_checked);
            $display("full observed   : yes");
            $display("========================================");
            $display("");
        end else begin
            $fatal(1, "FAIL: %0d FIFO errors detected", error_count);
        end

        $finish;
    end

endmodule
