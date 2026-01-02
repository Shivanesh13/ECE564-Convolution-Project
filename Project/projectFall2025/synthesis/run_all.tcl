
if {![info exists OUTPUT_DIR]} {
  set LOG_DIR "./"
}

redirect -tee $::env(OUTPUT_DIR)/logs/setup.log {source -echo setup.tcl} 
redirect -tee $::env(OUTPUT_DIR)/logs/read.log {source -echo read.tcl} 
redirect -tee $::env(OUTPUT_DIR)/logs/Constraints.log {source -echo Constraints.tcl} 
redirect -tee $::env(OUTPUT_DIR)/logs/CheckLatches.log {source -echo CheckLatches.tcl} 
redirect -tee $::env(OUTPUT_DIR)/logs/CompileAnalyze.log {source -echo CompileAnalyze.tcl}
exit
