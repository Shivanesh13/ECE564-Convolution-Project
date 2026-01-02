cmake_minimum_required(VERSION 3.26.5)
project(SV_DPI_MemCtrl CXX)

function(count_matching_files OUT_VAR)
  set(options RECURSE)
  set(oneValueArgs BASE)
  set(multiValueArgs PATTERNS EXCLUDE_REGEX)
  cmake_parse_arguments(CMF "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  if(NOT CMF_PATTERNS)
    message(FATAL_ERROR "count_matching_files: PATTERNS is required")
  endif()

  # sanitize BASE (remove trailing slash)
  if(CMF_BASE)
    string(REGEX REPLACE "/$" "" _base "${CMF_BASE}")
  endif()

  # build full patterns
  set(_patterns)
  foreach(p IN LISTS CMF_PATTERNS)
    if(DEFINED _base AND NOT _base STREQUAL "")
      list(APPEND _patterns "${_base}/${p}")
    else()
      list(APPEND _patterns "${p}")
    endif()
  endforeach()

  # glob args
  set(_glob_args LIST_DIRECTORIES FALSE)
  if(CMF_CONFIGURE_DEPENDS)
    list(APPEND _glob_args CONFIGURE_DEPENDS)
  endif()

  if(CMF_RECURSE)
    file(GLOB_RECURSE _all ${_glob_args} ${_patterns})
  else()
    file(GLOB _all ${_glob_args} ${_patterns})
  endif()

  list(REMOVE_DUPLICATES _all)

  # apply excludes
  set(_kept)
  foreach(f IN LISTS _all)
    set(_skip 0)
    foreach(rx IN LISTS CMF_EXCLUDE_REGEX)
      if(f MATCHES "${rx}")
        set(_skip 1)
        break()
      endif()
    endforeach()
    if(NOT _skip)
      list(APPEND _kept "${f}")
    endif()
  endforeach()

  list(SORT _kept) # deterministic order
  list(LENGTH _kept _n)
  set(${OUT_VAR} "${_n}" PARENT_SCOPE)
  set(${OUT_VAR}_FILES "${_kept}" PARENT_SCOPE)
endfunction()


# Force 64-bit vsim by default (matches a 64-bit mc_model.so)
# Helper: set a cache default only if not already provided (e.g., via -D or cache)
macro(cache_default VAR VALUE TYPE DOC)
  if(NOT DEFINED ${VAR})
    set(${VAR} "${VALUE}" CACHE ${TYPE} "${DOC}")
  endif()
endmacro()

cache_default(TEST       "-1"   STRING "VSIM arch flag; use -1 by default")
cache_default(CLASS      "ECE564" STRING "Course code")
cache_default(DEBUG      "-1"   STRING "Use debug inputs when -1; otherwise use input*.dat")
cache_default(DEBUG_DRAM "0"    STRING "Enable DRAM debug (1=yes, 0=no)")

message(STATUS "TEST=${TEST}, CLASS=${CLASS}, DEBUG=${DEBUG}, DEBUG_DRAM=${DEBUG_DRAM}")

file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/sim/logs")
message("STATUS Configured for: ${CLASS}")

# Choose pattern based on DEBUG
if("${DEBUG}" STREQUAL "0")
  set(INPUT_PATTERNS "input*.dat")
else()
  set(INPUT_PATTERNS "debug*.dat")
endif()

# Count once
count_matching_files(INPUT_FILE_COUNT
  BASE "${CMAKE_CURRENT_SOURCE_DIR}/inputs"
  PATTERNS ${INPUT_PATTERNS}
  CONFIGURE_DEPENDS
)

message(STATUS "DEBUG=${DEBUG} → using PATTERNS=${INPUT_PATTERNS}")
message(STATUS "INPUT_FILE_COUNT=${INPUT_FILE_COUNT}")

file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/sim/logs")
file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/sim/outputs")


# ------------------------------------------------------------------------------
# User-configurable knobs (set via -D...= on the cmake command)
# ------------------------------------------------------------------------------
# Plusargs are a *CMake list*; separate each +arg with semicolons
set(SIM_PLUSARGS 
	"+number_of_test=${INPUT_FILE_COUNT}"
	"+input_dir=${CMAKE_CURRENT_SOURCE_DIR}/inputs"
 	"+output_dir=${CMAKE_CURRENT_SOURCE_DIR}/outputs"
 	"+sim_output_dir=${CMAKE_CURRENT_BINARY_DIR}/sim/outputs"
 	"+log_file=${CMAKE_CURRENT_BINARY_DIR}/sim/logs/result.log"
 	"+test=${TEST}"
        "+class=${CLASS}"
        "+debug_run=${DEBUG}"
        "+mem_debug=${DEBUG_DRAM}"
)


# Force 64-bit vsim by default (matches a 64-bit mc_model.so)
set(VSIM_ARCH_FLAG "-64" CACHE STRING "vsim arch flag: \"-64\" for 64-bit, empty for 32-bit")

# Properly escape ';' for the -do script on old CMake
set(VSIM_DO_CMD "run -all\\; quit -f" CACHE STRING "vsim -do command (semicolon escaped)")

# If your site layout differs, override this to the correct platform dir
# e.g. .../questasim/lin64 or .../questasim/linux_aarch64
set(MODEL_TECH_DIR "" CACHE STRING "Override path to MODEL_TECH (e.g. /opt/questasim/linux_x86_64)")

# ------------------------------------------------------------------------------
# Find Questa/ModelSim tools
# ------------------------------------------------------------------------------
find_program(VSIM vsim)
find_program(VLOG vlog)
find_program(VLIB vlib)
if(NOT VSIM OR NOT VLOG OR NOT VLIB)
  message(FATAL_ERROR "Questa/ModelSim tools not found (need vsim, vlog, vlib) in PATH.")
endif()

# Derive install roots from vsim, unless MODEL_TECH_DIR is manually set
get_filename_component(_VSIM_DIR "${VSIM}" DIRECTORY)                 # .../questasim/bin
get_filename_component(_QUESTA_HOME_GUESS "${_VSIM_DIR}" DIRECTORY)   # .../questasim

if(NOT MODEL_TECH_DIR)
  # Default guess; adjust via -DMODEL_TECH_DIR=... if your site differs
  set(MODEL_TECH_DIR "${_QUESTA_HOME_GUESS}/linux_x86_64")
endif()

# Copy vendor modelsim.ini into the build dir so sv_std mapping is correct
set(MODELSIM_INI_SRC "${_QUESTA_HOME_GUESS}/modelsim.ini")
message("${_QUESTA_HOME_GUESS}/modelsim.ini")

# Try to find svdpi.h for include path (optional, but helps some compilers)
set(QUESTA_INCLUDE_DIR "$ENV{QUESTA_HOME}/include")
if(NOT EXISTS "${QUESTA_INCLUDE_DIR}/svdpi.h")
  set(QUESTA_INCLUDE_DIR "${_QUESTA_HOME_GUESS}/include")
endif()

# ------------------------------------------------------------------------------
# Compile SV into 'work' library (robust: copies modelsim.ini, exports MODEL_TECH)
# Put the stamp *inside* work/ so if work/ disappears, we recompile.
# ------------------------------------------------------------------------------
function(add_questa_compile target_name dut_file)
  set(build_dir "${CMAKE_CURRENT_BINARY_DIR}/${target_name}")
  set(work_dir  "${build_dir}/work")

  add_custom_command(
    OUTPUT "${work_dir}/.stamp"
    COMMAND "${CMAKE_COMMAND}" -E rm -rf "${work_dir}"
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${build_dir}"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${MODELSIM_INI_SRC}" "${build_dir}/modelsim.ini"
    COMMAND /usr/bin/env MODEL_TECH="${MODEL_TECH_DIR}" "${VLIB}" "${work_dir}"
    COMMAND /usr/bin/env MODEL_TECH="${MODEL_TECH_DIR}" "${VLOG}"
            -sv -work "${work_dir}" -modelsimini "${build_dir}/modelsim.ini"
            +acc=nprct -timescale=1ns/1ps -incdir "${CMAKE_CURRENT_SOURCE_DIR}"
            ${SV_COMMON_SOURCES} "${dut_file}"
    COMMAND "${CMAKE_COMMAND}" -E touch "${work_dir}/.stamp"
    DEPENDS ${SV_COMMON_SOURCES} "${dut_file}"
    COMMENT "Compiling SystemVerilog into '${work_dir}' (${target_name})"
  )
  add_custom_target(vlog-${target_name} DEPENDS "${work_dir}/.stamp")
  # ------------------------------------------------------------------------------
  # Run simulation (64-bit by default). vsim reads modelsim.ini from build dir.
  # ------------------------------------------------------------------------------
  add_custom_target(vsim-${target_name}-c
    COMMAND "${VSIM}" ${VSIM_ARCH_FLAG} -c -modelsimini ${build_dir}/modelsim.ini  ${build_dir}/work.tb -do "run -all\\; quit -f" ${SIM_PLUSARGS}  
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
    DEPENDS ${work_dir}/.stamp 
    COMMENT "Running vsim ${VSIM_ARCH_FLAG} with plusargs: ${SIM_PLUSARGS}"
  )
  
  add_custom_target(vsim-${target_name}
    COMMAND "${VSIM}" ${VSIM_ARCH_FLAG} -modelsimini ${build_dir}/modelsim.ini +fsdb+functions  ${build_dir}/work.tb -classdebug ${SIM_PLUSARGS}
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
    DEPENDS ${work_dir}/.stamp 
    COMMENT "Running vsim ${VSIM_ARCH_FLAG} with plusargs: ${SIM_PLUSARGS}"
  )
endfunction()

set(SV_COMMON_SOURCES
  "${CMAKE_CURRENT_SOURCE_DIR}/srcs/tb/dram.svp"
  "${CMAKE_CURRENT_SOURCE_DIR}/srcs/tb/tri_state_driver.sv"
  "${CMAKE_CURRENT_SOURCE_DIR}/srcs/tb/tb.sv"
)

add_questa_compile(dut    "${CMAKE_CURRENT_SOURCE_DIR}/srcs/rtl/dut.sv")
add_questa_compile(golden "${CMAKE_CURRENT_SOURCE_DIR}/srcs/tb/golden_dut.svp")


# =============================== DC SYNTH (drop-in) ===============================
# Runs Synopsys dc_shell using your scripts in ${SYNOPSYS_SRC_TCL_DIR}.
# - Honors optional:  -DDC_CLOCK_PER=2   (else setup.tcl defaults to 5.0)
# - Creates a stable build dir and output subdirs at configure time
# - Rebuilds when RTL or any Tcl script changes
# ================================================================================

# --- Config knobs (assume these are set earlier; keep here if not) -------------
# --- Look for dc_shell on the current PATH first ---
# If user passes -DDC_SHELL=... we honor that and skip the search.
if(NOT DEFINED DC_SHELL OR "${DC_SHELL}" STREQUAL "")
  find_program(DC_SHELL NAMES dc_shell dc_shell-xg-t)
  if(DC_SHELL)
    message(STATUS "Found dc_shell on PATH: ${DC_SHELL}")
  else()
    message(FATAL_ERROR
      "dc_shell not found on PATH.\n"
      "Add it to PATH or set -DDC_SHELL=/full/path/to/dc_shell")
  endif()
endif()

# Use the absolute path in COMMANDs (most robust):
# COMMAND "${DC_SHELL}" -no_gui -x "..."

# If you specifically want 'dc_shell' (no path) to work in COMMANDs,
# prepend its folder to the environment PATH for this CMake run:
get_filename_component(DC_SHELL_DIR "${DC_SHELL}" DIRECTORY)
set(ENV{PATH} "${DC_SHELL_DIR}:$ENV{PATH}")
message(STATUS "Augmented PATH with: ${DC_SHELL_DIR}")

set(DC_MODULE_NAME "dut" CACHE STRING "Top module/top design name")
# Optional clock override: cmake -DDC_CLOCK_PER=2
set(DC_CLOCK_PER "${DC_CLOCK_PER}" CACHE STRING "Clock period (ns). Leave blank to let setup.tcl default to 5.0" FORCE)

set(SYNOPSYS_SRC_TCL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/synthesis")
# Resolve your synthesis Tcl dir to an absolute path
if(IS_ABSOLUTE "${SYNOPSYS_SRC_TCL_DIR}")
  set(SYNOPSYS_SRC_TCL_ABS "${SYNOPSYS_SRC_TCL_DIR}")
else()
  set(SYNOPSYS_SRC_TCL_ABS "${CMAKE_CURRENT_SOURCE_DIR}/${SYNOPSYS_SRC_TCL_DIR}")
endif()
if(NOT IS_DIRECTORY "${SYNOPSYS_SRC_TCL_ABS}")
  message(FATAL_ERROR "SYNOPSYS_SRC_TCL_DIR does not exist: ${SYNOPSYS_SRC_TCL_ABS}")
endif()

# --- Build dir & “direct” directory generation (configure-time) ----------------
set(DC_BUILD_DIR "${CMAKE_CURRENT_BINARY_DIR}/dc")
file(MAKE_DIRECTORY "${DC_BUILD_DIR}")
file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/synth")
file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/synth/reports")
file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/synth/gl")
file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/synth/sdf")
file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/synth/logs")
file(MAKE_DIRECTORY "${DC_BUILD_DIR}/reports")
file(MAKE_DIRECTORY "${DC_BUILD_DIR}/gl")
file(MAKE_DIRECTORY "${DC_BUILD_DIR}/sdf")
file(MAKE_DIRECTORY "${DC_BUILD_DIR}/svf")

# --- Inputs (top-level RTL only; add more globs if needed) ---------------------
file(GLOB DC_RTL_V  "${CMAKE_CURRENT_SOURCE_DIR}/srcs/rtl/*.v")
file(GLOB DC_RTL_SV "${CMAKE_CURRENT_SOURCE_DIR}/srcs/rtl/*.sv")
file(GLOB REPORT_FILES "${CMAKE_CURRENT_SOURCE_DIR}/Project_report/*")

# Space-separated lists for env (CMake 2.8 safe)
string(REPLACE ";" " " DC_RTL_V_STR  "${DC_RTL_V}")
string(REPLACE ";" " " DC_RTL_SV_STR "${DC_RTL_SV}")

# Optional env export only when user provided DC_CLOCK_PER
unset(_DC_ENV_CLOCK_PER)
if(DEFINED DC_CLOCK_PER AND NOT "${DC_CLOCK_PER}" STREQUAL "")
  set(_DC_ENV_CLOCK_PER "DC_CLOCK_PER=${DC_CLOCK_PER}")
endif()

# Paths to the Tcl entry and companions
set(DC_TCL_RUNALL        "${SYNOPSYS_SRC_TCL_ABS}/run_all.tcl")
set(DC_TCL_SETUP         "${SYNOPSYS_SRC_TCL_ABS}/setup.tcl")
set(DC_TCL_READ          "${SYNOPSYS_SRC_TCL_ABS}/read.tcl")
set(DC_TCL_CHECK_LATCHES "${SYNOPSYS_SRC_TCL_ABS}/CheckLatches.tcl")   # you added this
set(DC_TCL_CONSTRAINTS   "${SYNOPSYS_SRC_TCL_ABS}/Constraints.tcl")
set(DC_TCL_COMPILE       "${SYNOPSYS_SRC_TCL_ABS}/CompileAnalyze.tcl")
set(DC_SETUP_FILE_OPT    "${SYNOPSYS_SRC_TCL_ABS}/.synopsys_dc.setup") # optional

# --- dc_shell invocation (complete) --------------------------------------------
add_custom_command(
  OUTPUT "${DC_BUILD_DIR}/.stamp"
  COMMAND "${CMAKE_COMMAND}" -E remove -f "${DC_BUILD_DIR}/.stamp"
  COMMAND "${CMAKE_COMMAND}" -E copy "${DC_SETUP_FILE_OPT}" "${DC_BUILD_DIR}"

  # Run dc_shell with env vars and a small Tcl prelude
  COMMAND /usr/bin/env
          ${_DC_ENV_CLOCK_PER}                  # only present if -DDC_CLOCK_PER=… was provided
          OUTPUT_DIR=${CMAKE_CURRENT_BINARY_DIR}/synth
          RTL_FILES=${DC_RTL_V_STR}
          RTL_SV_FILES=${DC_RTL_SV_STR}
          MODULE_NAME=${DC_MODULE_NAME}
          "${DC_SHELL}" -no_gui -x  "set_app_var search_path [concat {${SYNOPSYS_SRC_TCL_ABS}} [get_app_var search_path]]; source ${DC_TCL_RUNALL}"
  
  #COMMAND "${CMAKE_COMMAND}" -E touch "${DC_BUILD_DIR}/.stamp"
  WORKING_DIRECTORY "${DC_BUILD_DIR}"

  DEPENDS
    ${DC_RTL_V} ${DC_RTL_SV}
    "${DC_TCL_RUNALL}"
    "${DC_TCL_SETUP}"
    "${DC_TCL_READ}"
    "${DC_TCL_CHECK_LATCHES}"
    "${DC_TCL_CONSTRAINTS}"
    "${DC_TCL_COMPILE}"
    # Optional setup file (don’t fail if missing; DEPENDS is harmless if absent)
    "${DC_SETUP_FILE_OPT}"

  COMMENT "Synopsys DC: synthesize ${DC_MODULE_NAME} (CLK_PER via DC_CLOCK_PER or default in setup.tcl)"
  VERBATIM
)

add_custom_target(synth DEPENDS "${DC_BUILD_DIR}/.stamp")


# --- UNITY_ID drives the archive name: submission.<UNITY_ID>.tar.gz -----------
# Pass with:  cmake -S . -B build -DUNITY_ID=jdoe12
# If not passed, default to jdoe12.
if(NOT DEFINED UNITY_ID OR UNITY_ID STREQUAL "")
  set(UNITY_ID "jdoe12" CACHE STRING "")
endif()
# after project(...)
if(NOT DEFINED TEST OR "${TEST}" STREQUAL "")
  set(TEST "-1" CACHE STRING "")
endif()
message(STATUS "TEST = ${TEST}")

# Don't mutate the cache value; just make a sanitized copy for filenames.
set(_SUBMIT_ID "${UNITY_ID}")
string(REGEX REPLACE "[^A-Za-z0-9_.-]" "_" _SUBMIT_ID "${_SUBMIT_ID}")

# Files (you already defined the globs earlier)
set(DC_TCL_FILES
  "${CMAKE_CURRENT_SOURCE_DIR}/synthesis/CompileAnalyze.tcl"
)

set(PRESET_JSON
  "${CMAKE_CURRENT_SOURCE_DIR}/CMakePresets.json"
)

set(DC_FILES ${DC_RTL_V} ${DC_RTL_SV} ${DC_TCL} ${REPORT_FILES} ${PRESET_JSON})

# Make archive paths relative to the source root
set(DC_FILES_REL)
foreach(f IN LISTS DC_FILES)
  if(EXISTS "${f}")
    file(RELATIVE_PATH rf "${CMAKE_CURRENT_SOURCE_DIR}" "${f}")
    list(APPEND DC_FILES_REL "${rf}")
  endif()
endforeach()

find_program(TAR_EXECUTABLE NAMES tar gtar REQUIRED)
set(DC_ARCHIVE "${CMAKE_CURRENT_BINARY_DIR}/submission.${_SUBMIT_ID}.tar.gz")
set(PACK_ARCHIVE "${DC_ARCHIVE}")  # <-- add this

add_custom_target(compress
  COMMAND "${CMAKE_COMMAND}" -E echo "Creating ${DC_ARCHIVE}"
  COMMAND "${CMAKE_COMMAND}" -E make_directory "${CMAKE_CURRENT_BINARY_DIR}"
  # Remove old archive so size/date always reflect the new contents
  COMMAND "${CMAKE_COMMAND}" -E rm -f "${DC_ARCHIVE}"
  # Run tar from ${CMAKE_CURRENT_SOURCE_DIR} so ${DC_FILES_REL} paths are valid
  COMMAND "${CMAKE_COMMAND}" -E chdir "${CMAKE_CURRENT_SOURCE_DIR}"
          "${TAR_EXECUTABLE}" czf "${DC_ARCHIVE}" ${DC_FILES_REL} 
  USES_TERMINAL
  VERBATIM
)

