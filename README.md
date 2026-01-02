# ECE 564 SystemVerilog Convolution Project

This repository contains the ECE 564 Fall 2025 SystemVerilog convolution project, implementing a hardware-accelerated convolution operation for image processing applications.

## 📋 Project Overview

This project implements a convolution accelerator in SystemVerilog, designed for FPGA/ASIC implementation. The system performs convolution operations on image data with support for multiple test cases and includes both synthesizable RTL and behavioral reference models.

### Key Features
- **SystemVerilog RTL Implementation**: Synthesizable convolution module (`dut.sv`)
- **Reference Golden Model**: Behavioral SystemVerilog model for verification
- **Comprehensive Test Suite**: Multiple test cases including debug and full-scale inputs
- **Synthesis Scripts**: Design Compiler synthesis flow with timing/area analysis
- **CMake Build System**: Automated build and simulation environment
- **ModelSim Integration**: GUI and headless simulation support

## 🏗️ Project Structure

```
ECE564-Convolution-Project/
├── Project/                           # Project documentation and specifications
│   ├── fa25_ece564_Project2025_v01.pdf # Project specification document
│   ├── project_README.pdf             # Additional documentation
│   ├── SRAM_ops.docx                  # SRAM operations documentation
│   ├── projectFall2025/               # Main project directory
│   │   ├── CMakeLists.txt             # CMake build configuration
│   │   ├── CMakePresets.json          # Build presets and configurations
│   │   ├── README.md                  # Detailed project setup guide
│   │   ├── setup.sh                   # Environment setup script
│   │   ├── srcs/                      # Source files
│   │   │   ├── rtl/
│   │   │   │   └── dut.sv             # Main RTL implementation
│   │   │   └── tb/                    # Testbench files
│   │   │       ├── tb.sv              # Main testbench
│   │   │       ├── golden_dut.svp     # Reference model
│   │   │       └── tri_state_driver.sv
│   │   ├── inputs/                    # Test input data files
│   │   ├── outputs/                   # Expected output files
│   │   ├── images/                    # Test images (debug and input)
│   │   ├── scripts/                   # Python utility scripts
│   │   │   ├── conv.py                # Convolution utilities
│   │   │   ├── gen_outputs.sh         # Output generation script
│   │   │   └── img2svmem.py           # Image to memory conversion
│   │   ├── synthesis/                 # Synthesis scripts
│   │   │   ├── CompileAnalyze.tcl     # Design Compiler compilation
│   │   │   ├── Constraints.tcl        # Timing constraints
│   │   │   ├── run_all.tcl            # Complete synthesis flow
│   │   │   └── *.tcl                  # Additional synthesis scripts
│   │   └── Project_report/            # Project reports and documentation
│   └── projectFall2025.tar.gz         # Archived project files
├── Project_report/                    # Final project reports
│   ├── report.pdf                     # Project report
│   │── reports/                       # Synthesis and timing reports
│   └── cell_report_final.rpt          # Cell usage report
├── srcs/rtl/                          # Additional RTL files
│   └── dut.sv                         # Alternative RTL implementation
├── base_convo.sv                      # Base convolution module
├── dut_convo_working.sv               # Working convolution implementation
├── temp_dut_1.sv                      # Development version
├── .gitignore                         # Git ignore rules
├── CMakePresets.json                  # Root CMake configuration
└── README.md                          # This file
```

## 🚀 Quick Start

### Prerequisites
- **ModelSim/QuestaSim**: For RTL simulation
- **Synopsys Design Compiler**: For synthesis (optional)
- **CMake**: Build system
- **Bash shell**: For setup scripts

### Setup and Simulation

1. **Clone and navigate to project:**
   ```bash
   git clone https://github.com/Shivanesh13/ECE564-Convolution-Project.git
   cd ECE564-Convolution-Project/Project/projectFall2025
   ```

2. **Setup environment:**
   ```bash
   source setup.sh
   ```

3. **Build project:**
   ```bash
   mkdir build && cd build
   cmake .. --preset run  # For full test suite
   # OR
   cmake .. --preset debug  # For debug test cases
   ```

4. **Run simulation:**
   ```bash
   make vsim-dut           # Launch ModelSim GUI
   # OR
   make vsim-dut-c         # Run headless simulation
   ```

5. **Run reference model:**
   ```bash
   make vsim-golden        # Launch golden model in ModelSim
   ```

### Synthesis

1. **Navigate to build directory:**
   ```bash
   cd build
   ```

2. **Run synthesis:**
   ```bash
   make synth
   ```

3. **Check results:**
   - Timing reports: `synth/reports/`
   - Area reports: `synth/reports/`
   - Synthesized netlist: `synth/gl/`

## 📊 Test Cases

### Debug Cases (32x32 images)
- `debug0-3`: Small test cases for development

### Full Test Cases (1024x1024 images)
- `input0-5`: Complete test suite for grading

### Running Specific Tests
```bash
# Run specific test case
cmake .. --preset test2    # Run test case 2
make vsim-dut

# Run specific debug case
cmake .. --preset debug1   # Run debug case 1
make vsim-dut
```

## 🔧 Development Workflow

### Modifying RTL
1. Edit `srcs/rtl/dut.sv` with your implementation
2. Run simulation: `make vsim-dut`
3. In ModelSim: `make vlog-dut; restart -f; run -all`

### Adding Waveforms
1. Edit `do/waves.do` to add signals
2. In ModelSim: `do ../do/waves.do`

### Synthesis Optimization
```bash
# Change clock period
cmake .. -DDC_CLOCK_PER=4.0
make synth
```

## 📈 Performance Metrics

- **Target Clock Period**: Configurable (default: 10ns, optimized: 4ns)
- **Throughput**: Multiple pixels per clock cycle (pipelined)
- **Latency**: Optimized for real-time processing
- **Area**: Minimized resource utilization

## 📝 Documentation

- **Project Specification**: `Project/fa25_ece564_Project2025_v01.pdf`
- **Setup Guide**: `Project/projectFall2025/README.md`
- **Synthesis Reports**: `Project_report/reports/`
- **Final Report**: `Project_report/report.pdf`

## 🛠️ Tools and Technologies

- **HDL**: SystemVerilog IEEE 1800-2017
- **Simulation**: ModelSim/QuestaSim
- **Synthesis**: Synopsys Design Compiler
- **Build System**: CMake
- **Version Control**: Git
- **Documentation**: Markdown, PDF reports

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature-name`
3. Make your changes and test thoroughly
4. Commit changes: `git commit -am 'Add feature'`
5. Push to branch: `git push origin feature-name`
6. Submit a Pull Request

## 📞 Support

- **Course**: ECE 564 - Digital Systems Design
- **Institution**: Duke University
- **Semester**: Fall 2025

## 📄 License

This project is part of an academic course assignment. Please refer to course policies for usage and distribution guidelines.

---

**Note**: This project requires access to licensed EDA tools (ModelSim/QuestaSim, Design Compiler) typically available in university computer labs or through academic licenses.
