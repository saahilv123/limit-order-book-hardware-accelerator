module lob_engine_sva (
    input logic clk,
    input logic rst_n,
    input logic msg_valid,
    input logic ready,
    input logic update_valid
);

    property accepted_message_makes_engine_busy;
        @(posedge clk) disable iff (!rst_n)
        (msg_valid && ready) |=> !ready;
    endproperty

    property completion_returns_engine_ready;
        @(posedge clk) disable iff (!rst_n)
        update_valid |-> ready;
    endproperty

    property completion_is_single_cycle;
        @(posedge clk) disable iff (!rst_n)
        update_valid |=> !update_valid;
    endproperty

    assert property (accepted_message_makes_engine_busy)
        else $error("Engine remained ready after accepting a message");

    assert property (completion_returns_engine_ready)
        else $error("Engine completion did not return to ready state");

    assert property (completion_is_single_cycle)
        else $error("update_valid remained asserted for more than one cycle");

endmodule
