
# time information
set_time_format -unit ns -decimal_places 3


#create clocks
create_clock -name pll_in_clk -period 20 [get_ports {MAX10_CLK1_50}]

# name PLL clocks
set pll_sdram "clocks|altpll_component|auto_generated|pll1|clk[0]"
set clk_mem   "clocks|altpll_component|auto_generated|pll1|clk[1]"
set clk_sys    "clocks|altpll_component|auto_generated|pll1|clk[2]"

# pll clocks
derive_pll_clocks


# generated clocks

create_generated_clock -name clk_sdram -source [get_pins {clocks|altpll_component|auto_generated|pll1|clk[0]}] [get_ports {DRAM_CLK}]
create_generated_clock -name spiclk -source [get_pins {clocks|altpll_component|auto_generated|pll1|clk[2]}] -divide_by 2 [get_registers {controller:controller|spi_controller:spi|sck}]

# name SDRAM ports
set sdram_outputs [get_ports {DRAM_ADDR[*] DRAM_LDQM DRAM_UDQM DRAM_WE_N DRAM_CAS_N DRAM_RAS_N DRAM_CS_N DRAM_BA[*] DRAM_CKE}]
set sdram_dqoutputs [get_ports {DRAM_DQ[*]}]
set sdram_inputs  [get_ports {DRAM_DQ[*]}]


# clock groups



# clock uncertainty
derive_clock_uncertainty


# input delay
set_input_delay -clock clk_sdram -max 6.0 $sdram_inputs
set_input_delay -clock clk_sdram -min 4.0 $sdram_inputs

set_input_delay -clock $clk_sys .5 [get_ports {ARDUINO_IO[*]}]
set_input_delay -clock $clk_sys .5 [get_ports {GPIO[*]}]
set_input_delay -clock $clk_sys .5 [get_ports {KEY[*]}]

set_input_delay -clock $clk_mem .5 [get_ports {altera_reserved_tdi}]
set_input_delay -clock $clk_mem .5 [get_ports {altera_reserved_tms}]

#output delay
#set_output_delay -clock $clk_sdram -max  1.5 [get_ports DRAM_CLK]
#set_output_delay -clock $clk_sdram -min -0.8 [get_ports DRAM_CLK]
set_output_delay -clock clk_sdram -max  1.5 $sdram_outputs
set_output_delay -clock clk_sdram -max  1.5 $sdram_dqoutputs
set_output_delay -clock clk_sdram -min -0.8 $sdram_outputs
set_output_delay -clock clk_sdram -min -0.8 $sdram_dqoutputs

set_output_delay -clock $clk_sys .5 [get_ports {ARDUINO_IO[*]}]
set_output_delay -clock $clk_sys .5 [get_ports {GPIO[*]}]
set_output_delay -clock $clk_sys .5 [get_ports {VGA_R[*]}]
set_output_delay -clock $clk_sys .5 [get_ports {VGA_G[*]}]
set_output_delay -clock $clk_sys .5 [get_ports {VGA_B[*]}]
set_output_delay -clock $clk_sys .5 [get_ports {VGA_*S}]
set_output_delay -clock $clk_sys .5 [get_ports {LEDR[*]}]

set_output_delay -clock $clk_sys .5 [get_ports {altera_reserved_tdo}]

# false paths


# multicycle paths

set_multicycle_path -from {controller|cpu|*} -to {controller|cpu|eightthirtytwo_alu:alu|mulresult[*]} -setup -end 2
set_multicycle_path -from {controller|cpu|*} -to {controller|cpu|eightthirtytwo_alu:alu|mulresult[*]} -hold -end 2

# Move data window for SDRAM reads by 1 cycle
set_multicycle_path -from clk_sdram -to [get_clocks $clk_mem] -setup 2

# JTAG
#set ports [get_ports -nowarn {altera_reserved_tck}]
#if {[get_collection_size $ports] == 1} {
#  create_clock -name tck -period 100.000 [get_ports {altera_reserved_tck}]
#  set_clock_groups -exclusive -group altera_reserved_tck
#  set_output_delay -clock tck 20 [get_ports altera_reserved_tdo]
#  set_input_delay  -clock tck 20 [get_ports altera_reserved_tdi]
#  set_input_delay  -clock tck 20 [get_ports altera_reserved_tms]
#  set tck altera_reserved_tck
#  set tms altera_reserved_tms
#  set tdi altera_reserved_tdi
#  set tdo altera_reserved_tdo
#  set_false_path -from *                -to [get_ports $tdo]
#  set_false_path -from [get_ports $tms] -to *
#  set_false_path -from [get_ports $tdi] -to *
#}
