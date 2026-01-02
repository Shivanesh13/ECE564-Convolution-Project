
# setup name of the clock in your design.
  set clkname clk

# set variable "modname" to the name of topmost module in design
  set modname dut

# set variable "RTL_DIR" to the HDL directory w.r.t synthesis directory
  set RTL_DIR   ../srcs/rtl/  

# set variable "type" to a name that distinguishes this synthesis run
  set type tut1

#set the number of digits to be used for delay results
  set report_default_significant_digits 4

# Decide CLK_PER from env:DC_CLOCK_PER; otherwise default to 5.0
  if {[info exists ::env(DC_CLOCK_PER)] && $::env(DC_CLOCK_PER) ne ""} {
    set CLK_PER $::env(DC_CLOCK_PER)
  } elseif {![info exists CLK_PER]} {
    set CLK_PER 10.0
  }
  echo "\[setup.tcl\] CLK_PER=${CLK_PER}"

  set search_path [concat $search_path ${RTL_DIR}]

  set_svf -default ./svf/default.svf
