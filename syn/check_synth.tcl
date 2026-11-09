# Quick synthesizability check for one module (out-of-context, no I/O pins).
# Usage: vivado -mode batch -source syn/check_synth.tcl -tclargs <repo_root> <top>
set root [lindex $argv 0]
set top  [lindex $argv 1]
source $root/syn/part.tcl
read_verilog -sv [glob $root/rtl/*.sv]
synth_design -top $top -part $PART -mode out_of_context
report_utilization -file util_$top.rpt
report_timing_summary -file timing_$top.rpt
