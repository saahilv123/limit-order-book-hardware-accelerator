module lob_engine #(
    parameter int ORDER_ID_WIDTH = 10,
    parameter int PRICE_WIDTH = 8,
    parameter int QUANTITY_WIDTH = 16
)(
    input  logic                         clk,
    input  logic                         rst_n,

    input  logic                         msg_valid,
    input  logic [1:0]                   msg_opcode,
    input  logic [ORDER_ID_WIDTH-1:0]    msg_order_id,
    input  logic                         msg_side,
    input  logic [PRICE_WIDTH-1:0]       msg_price,
    input  logic [QUANTITY_WIDTH-1:0]    msg_quantity,

    output logic                         ready,
    output logic                         update_valid,
    output logic [PRICE_WIDTH-1:0]       best_bid,
    output logic [PRICE_WIDTH-1:0]       best_ask,
    output logic                         best_bid_valid,
    output logic                         best_ask_valid
);

    typedef enum logic [1:0] {
        IDLE,
        ORDER_WAIT,
        LEVEL_WAIT
    } engine_state_t;

    engine_state_t state;

    // Only compact metadata needs resettable flip-flops
    // The large order and quantity stores live in SRAM macros
    // and are never cleared on reset
    logic [1023:0] order_valid;
    logic [255:0] bid_occupied;
    logic [255:0] ask_occupied;

    logic [1:0] latched_opcode;
    logic [9:0] latched_order_id;
    logic latched_side;
    logic [7:0] latched_price;
    logic [15:0] latched_quantity;
    logic latched_order_valid;

    logic target_side;
    logic [7:0] target_price;
    logic [15:0] stored_order_quantity;

    logic order_sram_en;
    logic order_sram_we;
    logic [9:0] order_sram_addr;
    logic [31:0] order_sram_wdata;
    logic [31:0] order_sram_rdata;

    logic bid_sram_en;
    logic bid_sram_we;
    logic [7:0] bid_sram_addr;
    logic [31:0] bid_sram_wdata;
    logic [31:0] bid_sram_rdata;

    logic ask_sram_en;
    logic ask_sram_we;
    logic [7:0] ask_sram_addr;
    logic [31:0] ask_sram_wdata;
    logic [31:0] ask_sram_rdata;

    logic order_read_side;
    logic [7:0] order_read_price;
    logic [15:0] order_read_quantity;

    logic [31:0] current_level_quantity;
    logic [31:0] updated_level_quantity;
    logic [15:0] reduction_quantity;

    logic operation_updates_book;
    logic reduction_removes_order;

    assign ready = (state == IDLE);

    // Order SRAM word layout:
    // [24]    side
    // [23:16] price
    // [15:0]  quantity
    // [31:25] unused
    assign order_read_side = order_sram_rdata[24];
    assign order_read_price = order_sram_rdata[23:16];
    assign order_read_quantity = order_sram_rdata[15:0];

    always_comb begin
        if (latched_quantity >= stored_order_quantity)
            reduction_quantity = stored_order_quantity;
        else
            reduction_quantity = latched_quantity;
    end

    always_comb begin
        operation_updates_book = 1'b0;

        if (latched_opcode == 2'b00)
            operation_updates_book =
                !latched_order_valid && latched_quantity != 0;
        else if (latched_opcode == 2'b01 ||
                 latched_opcode == 2'b10)
            operation_updates_book = latched_order_valid;
    end

    assign reduction_removes_order =
        (latched_opcode == 2'b01 || latched_opcode == 2'b10) &&
        latched_order_valid &&
        (reduction_quantity >= stored_order_quantity);

    always_comb begin
        if (target_side == 1'b0) begin
            if (bid_occupied[target_price])
                current_level_quantity = bid_sram_rdata;
            else
                current_level_quantity = 32'b0;
        end else begin
            if (ask_occupied[target_price])
                current_level_quantity = ask_sram_rdata;
            else
                current_level_quantity = 32'b0;
        end

        updated_level_quantity = current_level_quantity;

        if (latched_opcode == 2'b00) begin
            updated_level_quantity =
                current_level_quantity + latched_quantity;
        end else if (latched_opcode == 2'b01 ||
                     latched_opcode == 2'b10) begin
            updated_level_quantity =
                current_level_quantity - reduction_quantity;
        end
    end

    // SRAM control is driven from the current pipeline state
    // Reads are synchronous, so their data is consumed on the following state
    always_comb begin
        order_sram_en = 1'b0;
        order_sram_we = 1'b0;
        order_sram_addr = 10'b0;
        order_sram_wdata = 32'b0;

        bid_sram_en = 1'b0;
        bid_sram_we = 1'b0;
        bid_sram_addr = 8'b0;
        bid_sram_wdata = 32'b0;

        ask_sram_en = 1'b0;
        ask_sram_we = 1'b0;
        ask_sram_addr = 8'b0;
        ask_sram_wdata = 32'b0;

        if (state == IDLE && msg_valid) begin
            order_sram_en = 1'b1;
            order_sram_we = 1'b0;
            order_sram_addr = msg_order_id;
        end

        if (state == ORDER_WAIT) begin
            if (latched_opcode == 2'b00 &&
                !latched_order_valid &&
                latched_quantity != 0) begin

                if (latched_side == 1'b0) begin
                    bid_sram_en = 1'b1;
                    bid_sram_we = 1'b0;
                    bid_sram_addr = latched_price;
                end else begin
                    ask_sram_en = 1'b1;
                    ask_sram_we = 1'b0;
                    ask_sram_addr = latched_price;
                end

            end else if ((latched_opcode == 2'b01 ||
                          latched_opcode == 2'b10) &&
                         latched_order_valid) begin

                if (order_read_side == 1'b0) begin
                    bid_sram_en = 1'b1;
                    bid_sram_we = 1'b0;
                    bid_sram_addr = order_read_price;
                end else begin
                    ask_sram_en = 1'b1;
                    ask_sram_we = 1'b0;
                    ask_sram_addr = order_read_price;
                end
            end
        end

        if (state == LEVEL_WAIT && operation_updates_book) begin
            if (target_side == 1'b0) begin
                bid_sram_en = 1'b1;
                bid_sram_we = 1'b1;
                bid_sram_addr = target_price;
                bid_sram_wdata = updated_level_quantity;
            end else begin
                ask_sram_en = 1'b1;
                ask_sram_we = 1'b1;
                ask_sram_addr = target_price;
                ask_sram_wdata = updated_level_quantity;
            end

            if (latched_opcode == 2'b00) begin
                order_sram_en = 1'b1;
                order_sram_we = 1'b1;
                order_sram_addr = latched_order_id;
                order_sram_wdata = {
                    7'b0,
                    latched_side,
                    latched_price,
                    latched_quantity
                };

            end else if (!reduction_removes_order) begin
                order_sram_en = 1'b1;
                order_sram_we = 1'b1;
                order_sram_addr = latched_order_id;
                order_sram_wdata = {
                    7'b0,
                    target_side,
                    target_price,
                    stored_order_quantity - reduction_quantity
                };
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            update_valid <= 1'b0;

            order_valid <= '0;
            bid_occupied <= '0;
            ask_occupied <= '0;

            latched_opcode <= '0;
            latched_order_id <= '0;
            latched_side <= 1'b0;
            latched_price <= '0;
            latched_quantity <= '0;
            latched_order_valid <= 1'b0;

            target_side <= 1'b0;
            target_price <= '0;
            stored_order_quantity <= '0;

        end else begin
            update_valid <= 1'b0;

            case (state)
                IDLE: begin
                    if (msg_valid) begin
                        latched_opcode <= msg_opcode;
                        latched_order_id <= msg_order_id;
                        latched_side <= msg_side;
                        latched_price <= msg_price;
                        latched_quantity <= msg_quantity;
                        latched_order_valid <= order_valid[msg_order_id];

                        state <= ORDER_WAIT;
                    end
                end

                ORDER_WAIT: begin
                    if (latched_opcode == 2'b00 &&
                        !latched_order_valid &&
                        latched_quantity != 0) begin

                        target_side <= latched_side;
                        target_price <= latched_price;
                        stored_order_quantity <= '0;

                        state <= LEVEL_WAIT;

                    end else if ((latched_opcode == 2'b01 ||
                                  latched_opcode == 2'b10) &&
                                 latched_order_valid) begin

                        target_side <= order_read_side;
                        target_price <= order_read_price;
                        stored_order_quantity <= order_read_quantity;

                        state <= LEVEL_WAIT;

                    end else begin
                        // Duplicate ADD, inactive reduction, zero-quantity ADD,
                        // or reserved opcode: accepted but no book state changes
                        update_valid <= 1'b1;
                        state <= IDLE;
                    end
                end

                LEVEL_WAIT: begin
                    update_valid <= 1'b1;

                    if (operation_updates_book) begin
                        if (target_side == 1'b0)
                            bid_occupied[target_price]
                                <= (updated_level_quantity != 0);
                        else
                            ask_occupied[target_price]
                                <= (updated_level_quantity != 0);

                        if (latched_opcode == 2'b00) begin
                            order_valid[latched_order_id] <= 1'b1;
                        end else if (reduction_removes_order) begin
                            order_valid[latched_order_id] <= 1'b0;
                        end
                    end

                    state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

    lob_order_sram order_memory (
        .clk   (clk),
        .en    (order_sram_en),
        .we    (order_sram_we),
        .addr  (order_sram_addr),
        .wdata (order_sram_wdata),
        .rdata (order_sram_rdata)
    );

    lob_price_sram bid_memory (
        .clk   (clk),
        .en    (bid_sram_en),
        .we    (bid_sram_we),
        .addr  (bid_sram_addr),
        .wdata (bid_sram_wdata),
        .rdata (bid_sram_rdata)
    );

    lob_price_sram ask_memory (
        .clk   (clk),
        .en    (ask_sram_en),
        .we    (ask_sram_we),
        .addr  (ask_sram_addr),
        .wdata (ask_sram_wdata),
        .rdata (ask_sram_rdata)
    );

    highest_set_bit_256 best_bid_encoder (
        .occupied (bid_occupied),
        .valid    (best_bid_valid),
        .index    (best_bid)
    );

    lowest_set_bit_256 best_ask_encoder (
        .occupied (ask_occupied),
        .valid    (best_ask_valid),
        .index    (best_ask)
    );

endmodule
