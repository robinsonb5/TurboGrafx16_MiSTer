
# time information
set_time_format -unit ns -decimal_places 3


#create clocks
create_clock -name pll_in_clk -period 20 [get_ports {clk50m}]

# pll clocks
derive_pll_clocks

# name PLL clocks
set pll_sdram "clocks|altpll_component|auto_generated|pll1|clk[0]"
set clk_fast   "clocks|altpll_component|auto_generated|pll1|clk[1]"
set clk_slow    "clocks|altpll_component|auto_generated|pll1|clk[2]"
set clk_med    "clocks|altpll_component|auto_generated|pll1|clk[3]"

# generated clocks
create_generated_clock -name clk_sdram -source [get_pins {clocks|altpll_component|auto_generated|pll1|clk[0]}] [get_ports {ram_clk}]
create_generated_clock -name clk_spi -source [get_pins $clk_fast] -divide_by 4 [get_nets {controller|spi_controller|sck}]

# name SDRAM ports
set sdram_outputs [get_ports {ram_d[*] ram_a[*] ram_ldqm ram_udqm ram_we ram_cas ram_ras ram_ba[*] }]
set sdram_inputs  [get_ports {ram_d[*]}]


# clock groups



# clock uncertainty
derive_clock_uncertainty


# input delay
set_input_delay -clock clk_sdram -max 6.5 $sdram_inputs
set_input_delay -clock clk_sdram -min 5.5 $sdram_inputs

set_input_delay -clock $clk_fast 0.5 [get_ports low_d[*]]
set_input_delay -clock $clk_fast 0.5 [get_ports ps2iec[*]]
set_input_delay -clock $clk_fast 0.5 [get_ports {ba_in dotclk_n ioef ir_data phi2_n reset_btn romlh spi_miso usart_cts}]


#output delay
#set_output_delay -clock $clk_sdram -max  1.5 [get_ports sm_clk]
#set_output_delay -clock $clk_sdram -min -0.8 [get_ports sm_clk]
set_output_delay -clock clk_sdram -max  1.5 $sdram_outputs
set_output_delay -clock clk_sdram -min -0.8 $sdram_outputs

set_output_delay -clock $clk_med 0.5 [get_ports low_d[*]]
set_output_delay -clock $clk_med 0.5 [get_ports low_a[*]]
set_output_delay -clock $clk_med 0.5 [get_ports ser_out*]
set_output_delay -clock $clk_med 0.5 [get_ports {game_out irq_out mmc_cs ps2iec_sel rw_out sa15_out}]
set_output_delay -clock $clk_med 0.5 [get_ports {sa_oe sd_dir sd_oe spi_clk spi_mosi}]

# false paths

#set_false_path -from [get_clocks {clocks|altpll_component|auto_generated|pll1|clk[2]}] -to [get_clocks {clk_spi}]
#set_false_path -from [get_clocks {clocks|altpll_component|auto_generated|pll1|clk[3]}] -to [get_clocks {clk_spi}]
#set_false_path -from [get_clocks {clk_spi}] -to [{clocks|altpll_component|auto_generated|pll1|clk[2]}]

set_false_path -to {sigma_*}
set_false_path -to {red[*]}
set_false_path -to {grn[*]}
set_false_path -to {blu[*]}
set_false_path -to {*sync_n}


# multicycle paths

set_multicycle_path -from {controller|eightthirtytwo_cpu:my832|*} -to {controller|eightthirtytwo_cpu:my832|eightthirtytwo_alu:alu|mulresult[*]} -setup -end 2
set_multicycle_path -from {controller|eightthirtytwo_cpu:my832|*} -to {controller|eightthirtytwo_cpu:my832|eightthirtytwo_alu:alu|mulresult[*]} -hold -end 2

# Adjust data window for SDRAM reads by 1 cycle
set_multicycle_path -from clk_sdram -to [get_clocks $clk_fast] -setup 2

# C64 IO signals are stable long before the IO entity writes them to the bus...
set_multicycle_path -to {low_a[*]} -setup -end 4
set_multicycle_path -to {low_a[*]} -hold -end 3
