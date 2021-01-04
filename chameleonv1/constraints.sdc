
# time information
set_time_format -unit ns -decimal_places 3


#create clocks
create_clock -name pll_in_clk -period 125 [get_ports {clk8}]

# pll clocks
derive_pll_clocks

# name PLL clocks
set pll_sdram "clocks|altpll_component|auto_generated|pll1|clk[0]"
set clk_fast  "clocks|altpll_component|auto_generated|pll1|clk[1]"
set clk_slow  "clocks|altpll_component|auto_generated|pll1|clk[2]"

# generated clocks
create_generated_clock -name clk_sdram -source [get_pins {clocks|altpll_component|auto_generated|pll1|clk[0]}] [get_ports {sd_clk}]
create_generated_clock -name clk_spi -source [get_pins $clk_fast] -divide_by 4 [get_nets {controller:controller|spi_controller:spi|sck}]


# name SDRAM ports
set sdram_outputs [get_ports {sd_addr[*] sd_ldqm sd_udqm sd_we_n sd_cas_n sd_ras_n sd_ba_* }]
set sdram_dqoutputs [get_ports {sd_data[*]}]
set sdram_inputs  [get_ports {sd_data[*]}]


# clock groups


# clock uncertainty
derive_clock_uncertainty


# MUX constraints
# On a relatively slow clock we can ignore these relatively safely

set_false_path -from {chameleon_io:myIO|mux_d_reg[*]} -to {mux_d[*]}
set_false_path -from {chameleon_io:myIO|mux_reg[*]} -to {mux[*]}

# SDRAM constraints
# input delay
set_input_delay -clock clk_sdram -max 3.0 $sdram_inputs
set_input_delay -clock clk_sdram -min 2.0 $sdram_inputs
# output delay
#set_output_delay -clock clk_sdram -max  1.5 [get_ports {sd_clk}]
#set_output_delay -clock clk_sdram -min  0.5 [get_ports {sd_clk}]

set_output_delay -clock clk_sdram -max  1.5 $sdram_outputs
set_output_delay -clock clk_sdram -max  1.5 $sdram_dqoutputs
#set_output_delay -clock clk_sdram -min -0.8 $sdram_outputs
set_output_delay -clock clk_sdram -min -0.8 $sdram_outputs
set_output_delay -clock clk_sdram -min -0.8 $sdram_dqoutputs

set_input_delay -clock $clk_fast 0.5 [get_ports {dotclock_n ioef_n phi2_n romlh_n spi_miso usart_cts}]
set_output_delay -clock $clk_fast 0.5 [get_ports {mux_d[*]}]


# false paths

set_false_path -from [get_clocks {clocks|altpll_component|auto_generated|pll1|clk[1]}] -to [get_clocks {pll_in_clk}]
set_false_path -from {gen_reset:myReset|nreset*} -to {reset_28}
set_false_path -from [get_clocks {clocks|altpll_component|auto_generated|pll1|clk[1]}] -to [get_clocks {clk_spi}]
set_false_path -from [get_clocks {clocks|altpll_component|auto_generated|pll1|clk[2]}] -to [get_clocks {clk_spi}]
set_false_path -from [get_clocks {clk_spi}] -to [get_clocks {clocks|altpll_component|auto_generated|pll1|clk[1]}]
set_false_path -from {clocks|altpll_component|auto_generated|pll1|clk[2]} -to {sd_clk}

set_false_path -to {sigma*}
set_false_path -to {red[*]}
set_false_path -to {grn[*]}
set_false_path -to {blu[*]}
set_false_path -to {n*Sync}

# multicycle paths

##set_multicycle_path -from {controller|eightthirtytwo_cpu|*} -to {controller|eightthirtytwo_cpu|eightthirtytwo_alu:alu|mulresult[*]} -setup -end 2
#set_multicycle_path -from {controller|eightthirtytwo_cpu|*} -to {controller|eightthirtytwo_cpu|eightthirtytwo_alu:alu|mulresult[*]} -hold -end 2

# Adjust data window for SDRAM reads by 1 cycle
set_multicycle_path -from clk_sdram -to [get_clocks $clk_fast] -setup 2


set_multicycle_path -from {chameleon_io:myIO|mux_reg[*]} -to {mux[*]} -setup -end 2

