module highest_set_bit_256 (
    input  logic [255:0] occupied,
    output logic         valid,
    output logic [7:0]   index
);

    logic [15:0] group_valid;
    logic [3:0] group_best [0:15];

    always_comb begin
        group_valid = '0;

        for (int group = 0; group < 16; group = group + 1) begin
            group_best[group] = '0;

            for (int bit_index = 0; bit_index < 16; bit_index = bit_index + 1) begin
                if (occupied[(group * 16) + bit_index]) begin
                    group_valid[group] = 1'b1;
                    group_best[group] = bit_index[3:0];
                end
            end
        end

        valid = 1'b0;
        index = '0;

        for (int group = 0; group < 16; group = group + 1) begin
            if (group_valid[group]) begin
                valid = 1'b1;
                index = {group[3:0], group_best[group]};
            end
        end
    end

endmodule
