# Limit Order Book Hardware Accelerator

This project implements a simplified **limit order book (LOB) hardware accelerator** in SystemVerilog. The design processes simplified ITCH-style order messages, supports **ADD**, **CANCEL**, and **EXECUTE** operations, and maintains order state, aggregate bid/ask quantities, and best-price outputs.

A Clock Domain Crossing (CDC) asynchronous FIFO separates the market-data input domain from the order-book engine, while six hard SRAM macros provide the main order and price-level storage.

# Features

- SystemVerilog limit order book engine
- Simplified 37-bit ITCH-style market-data interface
- ADD / CANCEL / EXECUTE order operations
- CDC-safe asynchronous FIFO with Gray-code pointer synchronization
- 1,024 tracked-order capacity
- 256 bid and 256 ask price levels
- Best-bid / best-ask tracking
- Six hard SRAM macros for order and price-level storage
- Self-checking verification with SVA, randomized traffic, and a C++ golden model

## Message Format

| Field | Width | Description |
|---|---|---|
| Opcode | 2 bits | ADD, CANCEL, EXECUTE, reserved |
| Order ID | 10 bits | Identifies one of 1,024 order slots |
| Side | 1 bit | Buy or sell |
| Price | 8 bits | 256 discrete price levels |
| Quantity | 16 bits | Order quantity |

## Memory Architecture

The physical implementation uses six instances of:

`sky130_sram_1kbyte_1rw1r_32x256_8`

- **4 SRAMs** form the 1,024-entry order store
- **1 SRAM** stores aggregate bid quantities
- **1 SRAM** stores aggregate ask quantities

Using hard SRAM macros avoids implementing the main storage arrays with large numbers of standard-cell flip-flops.

The SRAM macro views are treated as an external dependency and are not included in this repository.

# Verification

The design was verified using:

- Directed and randomized SystemVerilog testing
- SystemVerilog Assertions (SVA)
- A self-checking scoreboard
- A C++ golden model for reference behavior

A representative RTL regression completed **506 transactions successfully**.

# ASIC Implementation

The `lob_engine` was implemented in **OpenLane 2** using the **SKY130 PDK**, including hard-SRAM integration, physical implementation, timing closure, and physical verification.

## Detailed Placement

![Detailed placement](docs/detailed_placement.png)

*Detailed placement close-up showing rows of standard cells in the central logic region.*

## Routed Interconnect

![Routed interconnect](docs/routing_closeup.png)

*Post-route OpenROAD view showing standard-cell geometry, vias, and multi-layer interconnect.*

## Final GDSII

![Final GDSII](docs/final_layout.png)

*Final KLayout GDSII view after routing and physical verification.*

## Final Results

| Metric | Result |
|---|---|
| Technology | SKY130 |
| Clock target | ~35 MHz |
| Hard SRAM macros | 6 |
| Total hard SRAM capacity | 6 KB |
| Order capacity | 1,024 orders |
| Price levels | 256 bid + 256 ask |
| Die area | 3.24 mm² |
| Setup violations | 0 |
| Hold violations | 0 |
| DRC | Passed |
| LVS | Passed |
| Antenna | Passed |

# Tools

SystemVerilog, C++, Verilator, Yosys, OpenROAD, OpenSTA, OpenLane 2, KLayout, Netgen, SKY130

# Project Scope

This project is a simulated ASIC implementation and was not fabricated.
