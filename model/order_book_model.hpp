#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>

class OrderBookModel {
public:
    static constexpr std::size_t kNumOrders = 1024;
    static constexpr std::size_t kNumPriceLevels = 256;

    struct TopOfBook {
        std::optional<std::uint16_t> best_bid;
        std::optional<std::uint16_t> best_ask;
    };

    void reset();

    void apply(
        std::uint8_t opcode,
        std::uint16_t order_id,
        bool side,
        std::uint16_t price,
        std::uint32_t quantity
    );

    TopOfBook top_of_book() const;

    bool order_active(std::uint16_t order_id) const;
    std::uint32_t order_quantity(std::uint16_t order_id) const;

private:
    struct Order {
        bool valid = false;
        bool side = false;
        std::uint16_t price = 0;
        std::uint32_t quantity = 0;
    };

    std::array<Order, kNumOrders> orders_{};
    std::array<std::uint64_t, kNumPriceLevels> bid_quantity_{};
    std::array<std::uint64_t, kNumPriceLevels> ask_quantity_{};
};
