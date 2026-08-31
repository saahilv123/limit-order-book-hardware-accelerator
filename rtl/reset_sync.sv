module reset_sync (
    input  logic clk,
    input  logic arst_n,
    output logic rst_n
);

    logic sync_ff1;
    logic sync_ff2;

    always_ff @(posedge clk or negedge arst_n) begin
        if (!arst_n) begin
            sync_ff1 <= 1'b0;
            sync_ff2 <= 1'b0;
        end else begin
            sync_ff1 <= 1'b1;
            sync_ff2 <= sync_ff1;
        end
    end

    assign rst_n = sync_ff2;

endmodule
