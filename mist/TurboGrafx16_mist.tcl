source mist_pins.tcl
source mist_opts.tcl

set_global_assignment -name SDC_FILE tgfx16_mist.sdc
set_global_assignment -name SYSTEMVERILOG_FILE TGFX16_MiST.sv
set_global_assignment -name QIP_FILE ../rtl_nosoc/common_nosoc.qip
set_global_assignment -name QIP_FILE "mist-modules/mist_core.qip"
set_global_assignment -name QIP_FILE pll.qip
set_global_assignment -name QIP_FILE ../rtl/turbografx16_common.qip
set_global_assignment -name SIGNALTAP_FILE output_files/ram.stp
set_global_assignment -name SIGNALTAP_FILE output_files/dio.stp
set_global_assignment -name SIGNALTAP_FILE output_files/cpu.stp
set_global_assignment -name SIGNALTAP_FILE output_files/vram.stp
set_global_assignment -name SIGNALTAP_FILE output_files/bsram.stp
set_global_assignment -name CDF_FILE output_files/tgfx16_mist.cdf
set_global_assignment -name SIGNALTAP_FILE output_files/rom.stp
set_global_assignment -name SIGNALTAP_FILE output_files/vdc.stp
set_global_assignment -name SIGNALTAP_FILE output_files/spr.stp

set_global_assignment -name SIGNALTAP_FILE output_files/stp1.stp
set_global_assignment -name CDF_FILE output_files/Chain1.cdf
set_global_assignment -name SLD_FILE /home/amr/FPGA/Projects/TurboGrafx16/mist/output_files/stp1_auto_stripped.stp
set_global_assignment -name TOP_LEVEL_ENTITY TGFX16_MIST_TOP

