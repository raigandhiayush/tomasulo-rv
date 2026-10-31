# Non-project Vivado flow for FPGA synthesis, implementation, and bitstream generation.
set here  [file dirname [file normalize [info script]]]
set repo  [file dirname $here]
set part  xc7a100tcsg324-1
set stage [expr {[llength $argv] > 0 ? [lindex $argv 0] : "bit"}]
set hexa  [expr {[llength $argv] > 1 ? [lindex $argv 1] : ""}]
set hex   [file normalize [expr {$hexa ne "" ? $hexa : "$repo/ooo_tests/programs/top_mmio.hex"}]]
set core  [expr {[llength $argv] > 2 ? [lindex $argv 2] : "ooo"}]
set out   [expr {$core eq "ooo" ? "$here/build" : "$here/build_$core"}]

if {[lsearch -exact {synth impl bit} $stage] < 0} {
	error "stage must be synth, impl or bit (got '$stage')"
}
if {[lsearch -exact {ooo pipe_m pipe} $core] < 0} {
	error "core must be ooo, pipe_m or pipe (got '$core')"
}

# ---- program image ----------------------------------------------------------
if {![file readable $hex]} { error "program image not readable: $hex" }
set fh    [open $hex r]
set words {}
foreach line [split [read $fh] "\n"] {
	regsub {//.*$} $line {} line                    ;# $readmemh comments
	set line [string trim $line]
	if {$line eq ""} continue
	if {![regexp {^[0-9A-Fa-f]{8}$} $line]} { close $fh; error "$hex: bad word '$line'" }
	lappend words $line
}
close $fh
if {[llength $words] < 1 || [llength $words] > 1024} {
	error "$hex has [llength $words] words; instr_mem holds 1024"
}
file mkdir $out/mem_generator/imem_dmem $out/run
file copy -force $hex $out/mem_generator/imem_dmem/imem.hex
cd $out/run
puts "instr_mem image: $hex ([llength $words] words), core $core"

# missing $readmem file or an inferred latch is fatal
set_msg_config -id {Synth 8-4445} -new_severity ERROR
set_msg_config -id {Synth 8-327}  -new_severity ERROR

# ---- synthesis --------------------------------------------------------------
switch $core {
	ooo {
		set top     top_fpga_ooo
		set generic {}
		set rtl {
			ooo_rtl/top_fpga_ooo.v ooo_rtl/perf_counters.v ooo_rtl/pipe_ooo.v
			ooo_rtl/ooo_core.v ooo_rtl/ooo_frontend.v ooo_rtl/instr_queue.v
			ooo_rtl/ooo_decode.v ooo_rtl/ooo_dispatch.v ooo_rtl/rat.v
			ooo_rtl/regfile_2r1w.v ooo_rtl/rob.v ooo_rtl/rs_array.v
			ooo_rtl/alu_fu.v ooo_rtl/mul_unit.v ooo_rtl/div_unit.v ooo_rtl/lsu.v ooo_rtl/l1_dcache.v ooo_rtl/bpred.v ooo_rtl/mem_wait.v
			modules/memory.v
		}
	}
	pipe_m {
		set top     top_fpga_base
		set generic {-generic CORE=1}
		set rtl {
			baseline_fpga/top_fpga_base.v ooo_rtl/perf_counters.v
			baseline_m/pipeline_m.v baseline_m/IF_ID_m.v baseline_m/execute_m.v modules/wb.v
			ooo_rtl/mul_unit.v ooo_rtl/div_unit.v modules/memory.v
		}
	}
	pipe {
		set top     top_fpga_base
		set generic {-generic CORE=0}
		set rtl {
			baseline_fpga/top_fpga_base.v ooo_rtl/perf_counters.v
			modules/pipeline.v modules/IF_ID.v modules/execute.v modules/wb.v
			modules/memory.v
		}
	}
}
foreach f $rtl { read_verilog $repo/$f }
read_xdc $here/top_fpga_ooo.xdc

synth_design -top $top -part $part -include_dirs [list $repo/ooo_rtl $repo/modules] {*}$generic
write_checkpoint -force $out/post_synth.dcp
report_utilization    -file $out/post_synth_utilization.rpt
report_timing_summary -file $out/post_synth_timing.rpt
if {$stage eq "synth"} { exit }

# ---- implementation ---------------------------------------------------------
opt_design
place_design
route_design
write_checkpoint -force $out/post_route.dcp
report_utilization    -file $out/post_route_utilization.rpt
report_timing_summary -max_paths 10 -file $out/post_route_timing.rpt
report_drc            -file $out/post_route_drc.rpt

set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1 -nworst 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1 -nworst 1]]
puts "routed WNS = $wns ns, WHS = $whs ns"
if {$wns eq "" || $whs eq "" || $wns < 0 || $whs < 0} {
	error "timing not met (WNS '$wns', WHS '$whs'); see $out/post_route_timing.rpt"
}
if {$stage eq "impl"} { exit }

write_bitstream -force $out/$top.bit
