#!/usr/bin/env python3
"""
Cycle-accurate Python simulation of the systolic array.
Mimics the Verilog RTL + testbench timing to find the 1-cycle offset bug.
"""

import sys

# ─── Parameters ───
M_ROWS = 4
K_DIM  = 4
N_COLS = 4
FEED_CYCLES  = K_DIM + M_ROWS + N_COLS - 2   # 10 (fixed)
DRAIN_CYCLES = 1

# ─── Test 1 data ───
A = [[i + k + 1 for k in range(K_DIM)] for i in range(M_ROWS)]
B = [[k + j + 1 for j in range(N_COLS)] for k in range(K_DIM)]

print("A matrix:")
for row in A: print(f"  {row}")
print("B matrix:")
for row in B: print(f"  {row}")

# Expected C = A × B
expected = [[sum(A[i][k] * B[k][j] for k in range(K_DIM)) for j in range(N_COLS)] for i in range(M_ROWS)]
print("\nExpected C = A × B:")
for row in expected: print(f"  {row}")

# ─── PE simulation ───
class PE:
    def __init__(self):
        self.accum = 0
        self.a_out = 0
        self.b_out = 0

    def tick(self, a_in, b_in, en, clear_acc):
        """Simulate one posedge clk."""
        # Accumulation
        if clear_acc:
            self.accum = 0
        elif en:
            product = a_in * b_in
            self.accum += product
        # Data pass-through (always, decoupled from en)
        self.a_out = a_in
        self.b_out = b_in

# ─── Build PE array ───
pes = [[PE() for _ in range(N_COLS)] for _ in range(M_ROWS)]

# ─── Testbench feed logic (mimics staggered feeding) ───
# TB sets data BEFORE @(posedge clk), boundary reads at posedge

# FSM state
state = "IDLE"
feed_cnt = 0
drain_cnt = 0

# Trace log
trace_log = []

def boundary_a(i, c):
    """pe_a_in[i][0] = A[i][c-i] if c>=i and c-i<K_DIM, else 0"""
    if state == "FEED" and c >= i and (c - i) < K_DIM:
        return A[i][c - i]
    return 0

def boundary_b(j, c):
    """pe_b_in[0][j] = B[c-j][j] if c>=j and c-j<K_DIM, else 0"""
    if state == "FEED" and c >= j and (c - j) < K_DIM:
        return B[c - j][j]
    return 0

# ─── Simulate ───
# Mimics the testbench:
# 1. reset
# 2. wait(!busy) -> IDLE
# 3. @(posedge clk) -> one idle cycle
# 4. set data + valid
# 5. feed loop

cycle = 0
total_errors = 0

# Reset phase (3 cycles)
for _ in range(3):
    for i in range(M_ROWS):
        for j in range(N_COLS):
            pes[i][j].tick(0, 0, en=False, clear_acc=True)
    cycle += 1

# IDLE cycle
state = "IDLE"
for i in range(M_ROWS):
    for j in range(N_COLS):
        pes[i][j].tick(0, 0, en=False, clear_acc=True)
cycle += 1

# ─── TB sets data and valid (like the Verilog testbench) ───
# At this point, TB does:
#   a_data[ii] = A[ii][0] if 0>=ii else 0
#   b_data[jj] = B[0][jj] if 0>=jj else 0
#   a_valid = 1, b_valid = 1
# Then enters the feed loop

# ─── FEED phase ───
state = "FEED"
feed_cnt = 0

print(f"\n{'='*80}")
print(f"FEED phase: {FEED_CYCLES} cycles")
print(f"{'='*80}")

for c in range(FEED_CYCLES):
    # Compute boundary inputs for this cycle
    pe_a_in = [[0]*N_COLS for _ in range(M_ROWS)]
    pe_b_in = [[0]*N_COLS for _ in range(M_ROWS)]
    
    for i in range(M_ROWS):
        pe_a_in[i][0] = boundary_a(i, feed_cnt)
    for j in range(N_COLS):
        pe_b_in[0][j] = boundary_b(j, feed_cnt)
    
    # Internal wiring: A flows right, B flows down
    for i in range(M_ROWS):
        for j in range(N_COLS):
            if j > 0:
                pe_a_in[i][j] = pes[i][j-1].a_out
            if i > 0:
                pe_b_in[i][j] = pes[i-1][j].b_out
    
    # Tick all PEs
    for i in range(M_ROWS):
        for j in range(N_COLS):
            pes[i][j].tick(pe_a_in[i][j], pe_b_in[i][j], en=True, clear_acc=False)
    
    # Log trace
    trace_line = f"  cycle {c:2d} (feed_cnt={feed_cnt}): "
    trace_line += f"pe_a_in[0][0]={pe_a_in[0][0]:3d}, pe_b_in[0][0]={pe_b_in[0][0]:3d}, accum[0][0]={pes[0][0].accum:3d} | "
    trace_line += f"pe_a_in[0][1]={pe_a_in[0][1]:3d}, pe_b_in[0][1]={pe_b_in[0][1]:3d}, accum[0][1]={pes[0][1].accum:3d}"
    trace_log.append(trace_line)
    print(trace_line)
    
    feed_cnt += 1

# ─── DRAIN phase ───
print(f"\n{'='*80}")
print(f"DRAIN phase: {DRAIN_CYCLES} cycles")
print(f"{'='*80}")

state = "DRAIN"
drain_cnt = 0

for c in range(DRAIN_CYCLES):
    # All boundary inputs are 0 during drain
    pe_a_in = [[0]*N_COLS for _ in range(M_ROWS)]
    pe_b_in = [[0]*N_COLS for _ in range(M_ROWS)]
    
    # Internal wiring
    for i in range(M_ROWS):
        for j in range(N_COLS):
            if j > 0:
                pe_a_in[i][j] = pes[i][j-1].a_out
            if i > 0:
                pe_b_in[i][j] = pes[i-1][j].b_out
    
    # Tick all PEs (en=0 during drain)
    for i in range(M_ROWS):
        for j in range(N_COLS):
            pes[i][j].tick(pe_a_in[i][j], pe_b_in[i][j], en=False, clear_acc=False)
    
    trace_line = f"  drain {c}: "
    trace_line += f"accum[0][0]={pes[0][0].accum:3d}, accum[0][1]={pes[0][1].accum:3d}"
    trace_log.append(trace_line)
    print(trace_line)
    
    drain_cnt += 1

# ─── c_valid cycle (result capture) ───
state = "DONE"
print(f"\n{'='*80}")
print("c_valid asserted — capturing results")
print(f"{'='*80}")

# ─── Check results ───
print(f"\n{'='*80}")
print("RESULTS")
print(f"{'='*80}")

print("\nExpected:")
for row in expected:
    print(f"  {' '.join(f'{v:6d}' for v in row)}")

print("\nGot:")
for i in range(M_ROWS):
    row = [pes[i][j].accum for j in range(N_COLS)]
    print(f"  {' '.join(f'{v:6d}' for v in row)}")

print("\nDiff:")
for i in range(M_ROWS):
    for j in range(N_COLS):
        got = pes[i][j].accum
        exp = expected[i][j]
        if got != exp:
            print(f"  [{i}][{j}]: expected={exp}, got={got}, diff={exp-got}")
            total_errors += 1

if total_errors == 0:
    print("  ALL MATCH ✓")
else:
    print(f"\n  {total_errors} MISMATCHES")

# ─── Detailed trace for PE(0,0) ───
print(f"\n{'='*80}")
print("DETAILED TRACE: PE(0,0)")
print(f"{'='*80}")

# Re-simulate with detailed PE(0,0) trace
pes2 = [[PE() for _ in range(N_COLS)] for _ in range(M_ROWS)]
state = "IDLE"

# Reset
for _ in range(3):
    for i in range(M_ROWS):
        for j in range(N_COLS):
            pes2[i][j].tick(0, 0, en=False, clear_acc=True)

# IDLE
for i in range(M_ROWS):
    for j in range(N_COLS):
        pes2[i][j].tick(0, 0, en=False, clear_acc=True)

# FEED
state = "FEED"
feed_cnt = 0
running_sum = 0

for c in range(FEED_CYCLES):
    pe_a_in = [[0]*N_COLS for _ in range(M_ROWS)]
    pe_b_in = [[0]*N_COLS for _ in range(M_ROWS)]
    
    for i in range(M_ROWS):
        pe_a_in[i][0] = boundary_a(i, feed_cnt)
    for j in range(N_COLS):
        pe_b_in[0][j] = boundary_b(j, feed_cnt)
    
    for i in range(M_ROWS):
        for j in range(N_COLS):
            if j > 0:
                pe_a_in[i][j] = pes2[i][j-1].a_out
            if i > 0:
                pe_b_in[i][j] = pes2[i-1][j].b_out
    
    a0 = pe_a_in[0][0]
    b0 = pe_b_in[0][0]
    product = a0 * b0
    running_sum += product
    
    for i in range(M_ROWS):
        for j in range(N_COLS):
            pes2[i][j].tick(pe_a_in[i][j], pe_b_in[i][j], en=True, clear_acc=False)
    
    print(f"  feed cycle {c} (feed_cnt={feed_cnt}): "
          f"a_in={a0:3d}, b_in={b0:3d}, product={product:4d}, "
          f"accum={pes2[0][0].accum:3d}, expected_running={running_sum:3d}")
    
    feed_cnt += 1

# DRAIN
state = "DRAIN"
for c in range(DRAIN_CYCLES):
    pe_a_in = [[0]*N_COLS for _ in range(M_ROWS)]
    pe_b_in = [[0]*N_COLS for _ in range(M_ROWS)]
    for i in range(M_ROWS):
        for j in range(N_COLS):
            if j > 0:
                pe_a_in[i][j] = pes2[i][j-1].a_out
            if i > 0:
                pe_b_in[i][j] = pes2[i-1][j].b_out
    for i in range(M_ROWS):
        for j in range(N_COLS):
            pes2[i][j].tick(pe_a_in[i][j], pe_b_in[i][j], en=False, clear_acc=False)
    print(f"  drain {c}: accum={pes2[0][0].accum}")

print(f"\n  Final PE(0,0) = {pes2[0][0].accum}, expected = {expected[0][0]}")
