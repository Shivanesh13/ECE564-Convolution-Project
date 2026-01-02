# CheckLatches.tcl — abort the run if level-sensitive latches are present
# Run right after read.tcl

file mkdir ./reports

# Ensure we’re on the intended top design (setup.tcl sets 'modname')
if {[info exists modname]} {
  current_design $modname
} else {
  set cur [current_design]
  if {$cur eq ""} {
    echo "ERROR: CheckLatches.tcl: 'modname' not set and no current design."
    exit 2
  }
}

# Collect level-sensitive registers (latches)
set LATCHES   [all_registers -level_sensitive]
set N_LATCHES [sizeof_collection $LATCHES]
set LATCHES_RPT "./reports/latches_rtl.rpt"

# Always write a report (even if empty)
set fp [open $LATCHES_RPT "w"]
puts $fp "Latch report (level-sensitive registers)"
puts $fp "Design     : [current_design]"
puts $fp "Generated  : [clock format [clock seconds]]"
puts $fp "Latch count: $N_LATCHES"
if {$N_LATCHES > 0} {
  puts $fp [format "%-60s %s" "Instance" "RefCell"]
  puts $fp [string repeat "-" 78]
  foreach_in_collection r $LATCHES {
    set inst [get_object_name $r]
    # ref_name is the library cell name (e.g., DFFR_X1 or LATCH_X1)
    set ref  [get_attribute $r ref_name]
    puts $fp [format "%-60s %s" $inst $ref]
  }
}
close $fp

if {$N_LATCHES > 0} {
  echo "ERROR: Found $N_LATCHES latch(es). See $LATCHES_RPT"
  # Also echo instances for quick visibility in the log
  foreach_in_collection r $LATCHES {
    echo "  latch: [get_object_name $r]"
  }
  exit 2
} else {
  echo "OK: No latches detected at RTL. Report: $LATCHES_RPT"
}

