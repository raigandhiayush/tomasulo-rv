# Programs selected bitstream onto the Nexys A7 FPGA over USB-JTAG.
set here [file dirname [file normalize [info script]]]
set core [expr {[llength $argv] > 0 ? [lindex $argv 0] : "ooo"}]
switch $core {
	ooo     { set bit $here/build/top_fpga_ooo.bit }
	pipe_m  { set bit $here/build_pipe_m/top_fpga_base.bit }
	pipe    { set bit $here/build_pipe/top_fpga_base.bit }
	default { error "core must be ooo, pipe_m or pipe (got '$core')" }
}
if {![file readable $bit]} { error "no bitstream at $bit; run synth_vivado.tcl first" }

open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices xc7a100t*] 0]
if {$dev eq ""} { error "no xc7a100t on the JTAG chain" }
current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
puts "programmed $dev with $bit; press CPU_RESET to restart the program"
close_hw_manager
