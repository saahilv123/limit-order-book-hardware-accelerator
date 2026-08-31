module async_fifo_sva #(
    parameter int ADDR_WIDTH = 4
)(
    input logic                  wr_clk,
    input logic                  wr_rst_n,
    input logic                  wr_en,
    input logic                  full,
    input logic [ADDR_WIDTH:0]   wr_bin,
    input logic [ADDR_WIDTH:0]   wr_gray,

    input logic                  rd_clk,
    input logic                  rd_rst_n,
    input logic                  rd_en,
    input logic                  empty,
    input logic                  rd_valid,
    input logic [ADDR_WIDTH:0]   rd_bin,
    input logic [ADDR_WIDTH:0]   rd_gray
);

    property write_pointer_holds_when_full;
        @(posedge wr_clk) disable iff (!wr_rst_n)
        (wr_en && full) |=> $stable(wr_bin);
    endproperty

    property read_pointer_holds_when_empty;
        @(posedge rd_clk) disable iff (!rd_rst_n)
        (rd_en && empty) |=> $stable(rd_bin);
    endproperty

    property write_gray_changes_one_bit;
        @(posedge wr_clk) disable iff (!wr_rst_n)
        $onehot0(wr_gray ^ $past(wr_gray));
    endproperty

    property read_gray_changes_one_bit;
        @(posedge rd_clk) disable iff (!rd_rst_n)
        $onehot0(rd_gray ^ $past(rd_gray));
    endproperty

    property read_valid_follows_accepted_read;
        @(posedge rd_clk) disable iff (!rd_rst_n)
        (rd_en && !empty) |=> rd_valid;
    endproperty

    assert property (write_pointer_holds_when_full)
        else $error("FIFO write pointer moved while full");

    assert property (read_pointer_holds_when_empty)
        else $error("FIFO read pointer moved while empty");

    assert property (write_gray_changes_one_bit)
        else $error("FIFO write Gray pointer changed by more than one bit");

    assert property (read_gray_changes_one_bit)
        else $error("FIFO read Gray pointer changed by more than one bit");

    assert property (read_valid_follows_accepted_read)
        else $error("FIFO did not produce rd_valid after an accepted read");

endmodule
