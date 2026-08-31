#include "Vlob_engine.h"
#include "verilated.h"

#include "../model/order_book_model.hpp"

#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <random>
#include <string>

struct Coverage {
    std::uint64_t adds = 0;
    std::uint64_t cancels = 0;
    std::uint64_t executes = 0;
    std::uint64_t buy_adds = 0;
    std::uint64_t sell_adds = 0;
    std::uint64_t partial_reductions = 0;
    std::uint64_t full_reductions = 0;
};

static void tick(Vlob_engine& dut)
{
    dut.clk = 0;
    dut.eval();

    dut.clk = 1;
    dut.eval();

    dut.clk = 0;
    dut.eval();
}

static void reset_dut(Vlob_engine& dut)
{
    dut.rst_n = 0;
    dut.msg_valid = 0;
    dut.msg_opcode = 0;
    dut.msg_order_id = 0;
    dut.msg_side = 0;
    dut.msg_price = 0;
    dut.msg_quantity = 0;

    tick(dut);
    tick(dut);

    dut.rst_n = 1;

    int cycles = 0;
    while (!dut.ready && cycles < 2000) {
        tick(dut);
        ++cycles;
    }

    if (!dut.ready) {
        std::cerr << "FAIL: order-book initialization never completed\n";
        std::exit(1);
    }
}

static void compare_top(
    const Vlob_engine& dut,
    const OrderBookModel& model,
    std::uint64_t transaction_index
)
{
    const auto expected = model.top_of_book();

    const bool expected_bid_valid = expected.best_bid.has_value();
    const bool expected_ask_valid = expected.best_ask.has_value();

    if (static_cast<bool>(dut.best_bid_valid) != expected_bid_valid) {
        std::cerr
            << "FAIL at transaction " << transaction_index
            << ": best_bid_valid RTL=" << static_cast<int>(dut.best_bid_valid)
            << " REF=" << expected_bid_valid << "\n";
        std::exit(1);
    }

    if (expected_bid_valid &&
        static_cast<std::uint16_t>(dut.best_bid) != expected.best_bid.value()) {
        std::cerr
            << "FAIL at transaction " << transaction_index
            << ": best_bid RTL=" << static_cast<unsigned>(dut.best_bid)
            << " REF=" << expected.best_bid.value() << "\n";
        std::exit(1);
    }

    if (static_cast<bool>(dut.best_ask_valid) != expected_ask_valid) {
        std::cerr
            << "FAIL at transaction " << transaction_index
            << ": best_ask_valid RTL=" << static_cast<int>(dut.best_ask_valid)
            << " REF=" << expected_ask_valid << "\n";
        std::exit(1);
    }

    if (expected_ask_valid &&
        static_cast<std::uint16_t>(dut.best_ask) != expected.best_ask.value()) {
        std::cerr
            << "FAIL at transaction " << transaction_index
            << ": best_ask RTL=" << static_cast<unsigned>(dut.best_ask)
            << " REF=" << expected.best_ask.value() << "\n";
        std::exit(1);
    }
}

static void send_message(
    Vlob_engine& dut,
    OrderBookModel& model,
    Coverage& coverage,
    std::uint64_t transaction_index,
    std::uint8_t opcode,
    std::uint16_t order_id,
    bool side,
    std::uint16_t price,
    std::uint32_t quantity
)
{
    const bool was_active = model.order_active(order_id);
    const std::uint32_t old_quantity = model.order_quantity(order_id);

    dut.msg_opcode = opcode;
    dut.msg_order_id = order_id;
    dut.msg_side = side;
    dut.msg_price = price;
    dut.msg_quantity = quantity;
    dut.msg_valid = 1;

    tick(dut);

    dut.msg_valid = 0;
    dut.eval();

    model.apply(opcode, order_id, side, price, quantity);

    if (opcode == 0) {
        ++coverage.adds;
        if (!side)
            ++coverage.buy_adds;
        else
            ++coverage.sell_adds;
    } else if (opcode == 1) {
        ++coverage.cancels;
    } else if (opcode == 2) {
        ++coverage.executes;
    }

    if ((opcode == 1 || opcode == 2) && was_active) {
        if (quantity >= old_quantity)
            ++coverage.full_reductions;
        else
            ++coverage.partial_reductions;
    }

    compare_top(dut, model, transaction_index);
}

static std::uint16_t find_inactive_order(
    const OrderBookModel& model,
    std::mt19937& rng
)
{
    std::uniform_int_distribution<int> start_dist(
        0,
        static_cast<int>(OrderBookModel::kNumOrders) - 1
    );

    std::uint16_t id =
        static_cast<std::uint16_t>(start_dist(rng));

    for (std::size_t attempt = 0;
         attempt < OrderBookModel::kNumOrders;
         ++attempt) {
        if (!model.order_active(id))
            return id;

        id = static_cast<std::uint16_t>(
            (id + 1) % OrderBookModel::kNumOrders
        );
    }

    return static_cast<std::uint16_t>(OrderBookModel::kNumOrders);
}

static std::uint16_t find_active_order(
    const OrderBookModel& model,
    std::mt19937& rng
)
{
    std::uniform_int_distribution<int> start_dist(
        0,
        static_cast<int>(OrderBookModel::kNumOrders) - 1
    );

    std::uint16_t id =
        static_cast<std::uint16_t>(start_dist(rng));

    for (std::size_t attempt = 0;
         attempt < OrderBookModel::kNumOrders;
         ++attempt) {
        if (model.order_active(id))
            return id;

        id = static_cast<std::uint16_t>(
            (id + 1) % OrderBookModel::kNumOrders
        );
    }

    return static_cast<std::uint16_t>(OrderBookModel::kNumOrders);
}

int main(int argc, char** argv)
{
    Verilated::commandArgs(argc, argv);

    std::uint32_t seed = 1;
    std::uint64_t random_transactions = 10000;

    if (argc >= 2)
        seed = static_cast<std::uint32_t>(std::stoul(argv[1]));

    if (argc >= 3)
        random_transactions = std::stoull(argv[2]);

    Vlob_engine dut;
    OrderBookModel model;
    Coverage coverage;

    model.reset();
    reset_dut(dut);

    std::uint64_t transaction_index = 0;

    // Directed tests exercise known top-of-book transitions first.
    send_message(dut, model, coverage, ++transaction_index, 0, 1, false, 100, 50);
    send_message(dut, model, coverage, ++transaction_index, 0, 2, false, 105, 30);
    send_message(dut, model, coverage, ++transaction_index, 0, 3, true, 110, 40);
    send_message(dut, model, coverage, ++transaction_index, 0, 4, true, 108, 25);
    send_message(dut, model, coverage, ++transaction_index, 1, 2, false, 0, 10);
    send_message(dut, model, coverage, ++transaction_index, 2, 4, false, 0, 25);

    std::mt19937 rng(seed);
    std::uniform_int_distribution<int> choice_dist(0, 99);
    std::uniform_int_distribution<int> side_dist(0, 1);
    std::uniform_int_distribution<int> price_dist(
        1,
        static_cast<int>(OrderBookModel::kNumPriceLevels) - 2
    );
    std::uniform_int_distribution<int> quantity_dist(1, 500);

    for (std::uint64_t i = 0; i < random_transactions; ++i) {
        const int choice = choice_dist(rng);

        if (choice < 60) {
            const std::uint16_t id =
                find_inactive_order(model, rng);

            if (id >= OrderBookModel::kNumOrders)
                continue;

            send_message(
                dut,
                model,
                coverage,
                ++transaction_index,
                0,
                id,
                side_dist(rng) != 0,
                static_cast<std::uint16_t>(price_dist(rng)),
                static_cast<std::uint32_t>(quantity_dist(rng))
            );
        } else {
            const std::uint16_t id =
                find_active_order(model, rng);

            if (id >= OrderBookModel::kNumOrders)
                continue;

            const std::uint32_t current_quantity =
                model.order_quantity(id);

            std::uniform_int_distribution<std::uint32_t> reduction_dist(
                1,
                current_quantity + 20
            );

            send_message(
                dut,
                model,
                coverage,
                ++transaction_index,
                choice < 80 ? 1 : 2,
                id,
                false,
                0,
                reduction_dist(rng)
            );
        }
    }

    std::cout << "\n";
    std::cout << "========================================\n";
    std::cout << "PASS: C++ golden-model regression\n";
    std::cout << "seed                 : " << seed << "\n";
    std::cout << "transactions         : " << transaction_index << "\n";
    std::cout << "adds                 : " << coverage.adds << "\n";
    std::cout << "  buy adds            : " << coverage.buy_adds << "\n";
    std::cout << "  sell adds           : " << coverage.sell_adds << "\n";
    std::cout << "cancels              : " << coverage.cancels << "\n";
    std::cout << "executes             : " << coverage.executes << "\n";
    std::cout << "partial reductions   : " << coverage.partial_reductions << "\n";
    std::cout << "full reductions      : " << coverage.full_reductions << "\n";
    std::cout << "========================================\n";
    std::cout << "\n";

    dut.final();
    return 0;
}
