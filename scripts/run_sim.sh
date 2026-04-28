#!/bin/bash
# ============================================================================
# Simulation script for Systolic Array Matrix Multiplier
# Usage: ./scripts/run_sim.sh [OPTIONS]
#   --rows M     Number of rows in A (default: 4)
#   --cols N     Number of columns in B (default: 4)
#   --k K        Shared dimension (default: 4)
#   --width W    Data bit width (default: 8)
#   --gui        Open GTKWave after simulation
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
SRC_DIR="$ROOT_DIR/src"
TB_DIR="$ROOT_DIR/tb"
BUILD_DIR="$ROOT_DIR/build"

# Defaults
M_ROWS=4
K_DIM=4
N_COLS=4
DATA_WIDTH=8
ACCUM_WIDTH=32
GUI=false

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --rows)  M_ROWS=$2; shift 2 ;;
        --cols)  N_COLS=$2; shift 2 ;;
        --k)     K_DIM=$2;  shift 2 ;;
        --width) DATA_WIDTH=$2; shift 2 ;;
        --gui)   GUI=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

ACCUM_WIDTH=$((DATA_WIDTH * 4))

mkdir -p "$BUILD_DIR"

echo "============================================"
echo " Systolic Array Matrix Multiplier"
echo " M=$M_ROWS  K=$K_DIM  N=$N_COLS"
echo " DATA_WIDTH=$DATA_WIDTH  ACCUM_WIDTH=$ACCUM_WIDTH"
echo "============================================"

# Generate parameterized testbench
TB_GEN="$BUILD_DIR/tb_systolic_array.v"
sed -e "s/parameter M_ROWS     = [0-9]*/parameter M_ROWS     = $M_ROWS/" \
    -e "s/parameter K_DIM      = [0-9]*/parameter K_DIM      = $K_DIM/" \
    -e "s/parameter N_COLS     = [0-9]*/parameter N_COLS     = $N_COLS/" \
    -e "s/parameter DATA_WIDTH = [0-9]*/parameter DATA_WIDTH = $DATA_WIDTH/" \
    -e "s/parameter ACCUM_WIDTH = [0-9]*/parameter ACCUM_WIDTH = $ACCUM_WIDTH/" \
    "$TB_DIR/tb_systolic_array.v" > "$TB_GEN"

# Compile
echo "[1/3] Compiling..."
iverilog -g2012 -o "$BUILD_DIR/systolic_array.vvp" \
    "$SRC_DIR/pe.v" \
    "$SRC_DIR/systolic_array.v" \
    "$TB_GEN"

# Simulate
echo "[2/3] Simulating..."
cd "$BUILD_DIR"
vvp systolic_array.vvp

# Waveform
if $GUI && [ -f systolic_array.vcd ]; then
    echo "[3/3] Opening GTKWave..."
    gtkwave systolic_array.vcd &
else
    echo "[3/3] Done. VCD waveform: $BUILD_DIR/systolic_array.vcd"
fi
