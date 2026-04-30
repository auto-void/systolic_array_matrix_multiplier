# ============================================================================
# Makefile for Systolic Array Matrix Multiplier
# Simulator: Verilator (--binary mode, generates native executable)
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
VERILATOR := verilator
GTKWAVE   := gtkwave

# Source files
SRCS     := $(SRC_DIR)/pe.v $(SRC_DIR)/systolic_array.v
TB       := $(TB_DIR)/tb_systolic_array.v
OVF_TB   := $(TB_DIR)/tb_overflow.v

# Verilator output dirs and executables
SIM_DIR  := $(BUILD)/sim_main
SIM_BIN  := $(SIM_DIR)/Vtb_systolic_array
OVF_DIR  := $(BUILD)/overflow
OVF_BIN  := $(OVF_DIR)/Vtb_overflow

# Verilator common flags
VFLAGS   := --binary -j 0 --timing -Wno-fatal

# Parameter defines passed to Verilator
DEFINES  := -DM_ROWS=$(M) -DK_DIM=$(K) -DN_COLS=$(N) -DDATA_WIDTH=$(W) -DACCUM_WIDTH=$(AW)

.PHONY: all sim overflow neg_overflow wave clean help

all: sim overflow

# ----------------------------------------------------------------
# Main simulation
# ----------------------------------------------------------------
$(SIM_BIN): $(SRCS) $(TB) | $(BUILD)
	@echo "========================================="
	@echo " M=$(M) K=$(K) N=$(N) W=$(W) AW=$(AW)"
	@echo "========================================="
	$(VERILATOR) $(VFLAGS) $(DEFINES) -Mdir $(SIM_DIR) \
		--top-module tb_systolic_array $(SRCS) $(TB)

sim: $(SIM_BIN)
	$(SIM_BIN)

# ----------------------------------------------------------------
# Overflow test
# ----------------------------------------------------------------
$(OVF_BIN): $(SRCS) $(OVF_TB) | $(BUILD)
	$(VERILATOR) $(VFLAGS) -Mdir $(OVF_DIR) \
		--top-module tb_overflow $(SRCS) $(OVF_TB)

overflow: $(OVF_BIN)
	$(OVF_BIN)

# ----------------------------------------------------------------
# Negative overflow test (K_DIM=4 to trigger negative saturation)
# ----------------------------------------------------------------
NEG_OVF_DIR  := $(BUILD)/neg_overflow
NEG_OVF_BIN  := $(NEG_OVF_DIR)/Vtb_overflow

$(NEG_OVF_BIN): $(SRCS) $(OVF_TB) | $(BUILD)
	$(VERILATOR) $(VFLAGS) -Mdir $(NEG_OVF_DIR) \
		--top-module tb_overflow $(SRCS) $(OVF_TB) \
		-DM_ROWS=2 -DK_DIM=4 -DN_COLS=2 -DDATA_WIDTH=4 -DACCUM_WIDTH=8

neg_overflow: $(NEG_OVF_BIN)
	$(NEG_OVF_BIN)

# ----------------------------------------------------------------
# Waveform (separate build dir to avoid recompiling sim)
# ----------------------------------------------------------------
WAVE_DIR  := $(BUILD)/wave
WAVE_BIN  := $(WAVE_DIR)/Vtb_systolic_array

$(WAVE_BIN): $(SRCS) $(TB) | $(BUILD)
	$(VERILATOR) $(VFLAGS) --trace $(DEFINES) -Mdir $(WAVE_DIR) \
		--top-module tb_systolic_array $(SRCS) $(TB)

wave: $(WAVE_BIN)
	$(WAVE_BIN) +verilator+traceoff
	$(GTKWAVE) systolic_array.vcd &

# ----------------------------------------------------------------
$(BUILD):
	mkdir -p $(BUILD)

clean:
	rm -rf $(BUILD)

help:
	@echo "Usage:"
	@echo "  make all              - sim + overflow (default)"
	@echo "  make sim              - Compile and run simulation (default 4x4x4)"
	@echo "  make sim M=8 K=8 N=8  - 8x8 x 8x8 matrix multiply"
	@echo "  make sim M=3 K=5 N=7  - 3x5 x 5x7 matrix multiply"
	@echo "  make sim W=16         - 16-bit data width"
	@echo "  make overflow         - Overflow/saturation test (4-bit data, 8-bit accum)"
	@echo "  make wave             - Run simulation and open GTKWave"
	@echo "  make clean            - Remove build artifacts"
