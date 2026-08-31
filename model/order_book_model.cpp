#include "order_book_model.hpp"

#include <algorithm>

void OrderBookModel::reset()
{
    orders_.fill(Order{});
    bid_quantity_.fill(0);
    ask_quantity_.fill(0);
}

void OrderBookModel::apply(
    std::uint8_t opcode,
    std::uint16_t order_id,
    bool side,
    std::uint16_t price,
    std::uint32_t quantity
)
{
    if (order_id >= kNumOrders)
        return;

    if (opcode == 0) {
        if (price >= kNumPriceLevels || orders_[order_id].valid)
            return;

        orders_[order_id].valid = true;
        orders_[order_id].side = side;
        orders_[order_id].price = price;
        orders_[order_id].quantity = quantity;

        if (!side)
            bid_quantity_[price] += quantity;
        else
            ask_quantity_[price] += quantity;

        return;
    }

    if (opcode != 1 && opcode != 2)
        return;

    Order& order = orders_[order_id];

    if (!order.valid)
        return;

    const std::uint32_t reduction =
        std::min(quantity, order.quantity);

    if (!order.side)
        bid_quantity_[order.price] -= reduction;
    else
        ask_quantity_[order.price] -= reduction;

    if (reduction == order.quantity) {
        order = Order{};
    } else {
        order.quantity -= reduction;
    }
}

OrderBookModel::TopOfBook OrderBookModel::top_of_book() const
{
    TopOfBook result;

    for (int price = static_cast<int>(kNumPriceLevels) - 1; price >= 0; price--) {
        if (bid_quantity_[price] != 0) {
            result.best_bid = static_cast<std::uint16_t>(price);
            break;
        }
    }

    for (std::size_t price = 0; price < kNumPriceLevels; price++) {
        if (ask_quantity_[price] != 0) {
            result.best_ask = static_cast<std::uint16_t>(price);
            break;
        }
    }

    return result;
}

bool OrderBookModel::order_active(std::uint16_t order_id) const
{
    if (order_id >= kNumOrders)
        return false;

    return orders_[order_id].valid;
}

std::uint32_t OrderBookModel::order_quantity(std::uint16_t order_id) const
{
    if (order_id >= kNumOrders || !orders_[order_id].valid)
        return 0;

    return orders_[order_id].quantity;
}
