create_clock -name book_clk -period 28.6 [get_ports clk]

set_false_path -from [get_ports rst_n]

set_input_delay 0.5 -clock book_clk [get_ports {msg_valid msg_side}]
set_input_delay 0.5 -clock book_clk [get_ports msg_opcode*]
set_input_delay 0.5 -clock book_clk [get_ports msg_order_id*]
set_input_delay 0.5 -clock book_clk [get_ports msg_price*]
set_input_delay 0.5 -clock book_clk [get_ports msg_quantity*]

set_output_delay 0.5 -clock book_clk [get_ports {ready best_bid_valid best_ask_valid}]
set_output_delay 0.5 -clock book_clk [get_ports best_bid*]
set_output_delay 0.5 -clock book_clk [get_ports best_ask*]
