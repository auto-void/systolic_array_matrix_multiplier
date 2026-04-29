# ============================================================================
# Makefile for Systolic Array Matrix Multiplier
# ============================================================================

# Configurable parameters (override via: make sim M=8 K=8 N=8 W=16)
M        ?= 4
K        ?= 4
N        ?= 4
W        ?= 8
AW       ?= $(shell echo "$$(( $(W) * 4 ))")

# Directories
SRC_DIR  := src
TB_DIR   := tb
BUILD    := build

# Tools
IVERILOG := iverilog
VVP      := vvp
GTKWAVE  := gtkwave

# Files
SRCS     := $(SRC_DIR)/pe.v $(SRC_DIR)/systolic_array.v
TB       := $(TB_DIR)/tb_systolic_array.v
VVP_OUT  := $(BUILD)/systolic_array.vvp
VCD_OUT  := $(BUILD)/systolic_array.vcd
OVF_TB   := $(TB_DIR)/tb_overflow.v
OVF_VVP  := $(BUILD)/overflow.vvp

# Parameter flags for iverilog
DEFINES  := -DM_ROWS=$(M) -DK_DIM=$(K) -DN_COLS=$(N) -DDATA_WIDTH=$(W) -DACCUM_WIDTH=$(AW)

.PHONY: all sim overflow wave clean help

all: sim

# Compile
$(VVP_OUT): $(SRCS) $(TB) | $(BUILD)
	@echo "========================================="
	@echo " M=$(M) K=$(K) N=$(N) W=$(W) AW=$(AW)"
	@echo "========================================="
	$(IVERILOG) -g2012 $(DEFINES) -o $@ $^

# Simulate
sim: $(VVP_OUT)
	$(VVP) $<

# Overflow test
$(OVF_VVP): $(SRCS) $(OVF_TB) | $(BUILD)
	$(IVERILOG) -g2012 -o $@ $^

overflow: $(OVF_VVP)
	$(VVP) $<

# Open waveform
wave: sim
	$(GTKWAVE) $(VCD_OUT) &

$(BUILD):
	mkdir -p $(BUILD)

clean:
	rm -rf $(BUILD)

help:
	@echo "Usage:"
	@echo "  make sim              - Compile and run simulation (default 4×4×4)"
	@echo "  make sim M=8 K=8 N=8  - 8×8 × 8×8 matrix multiply"
	@echo "  make sim M=3 K=5 N=7  - 3×5 × 5×7 matrix multiply"
	@echo "  make sim W=16         - 16-bit data width"
	@echo "  make overflow         - Overflow/saturation test (4-bit data, 8-bit accum)"
	@echo "  make wave             - Run simulation and open GTKWave"
	@echo "  make clean            - Remove build artifacts"
