#!/usr/bin/env python3
"""
Verify the FEED_CYCLES bug: data entering boundary at the last FEED cycle
arrives at PE one cycle too late (DRAIN phase, en=0).
"""

M, K, N = 4, 4, 4
FEED_CYCLES_CURRENT = K + max(M, N) - 1   # 7 (current, WRONG)
FEED_CYCLES_FIXED   = K + M + N - 2        # 9 (correct)

print(f"Current FEED_CYCLES = {FEED_CYCLES_CURRENT}")
print(f"Fixed   FEED_CYCLES = {FEED_CYCLES_FIXED}")
print()

# For each PE(i,j), find the last accumulation cycle
# Last A[i][k] enters boundary at cycle k+i, arrives at PE(i,0) at cycle k+i+1
# Last B[k][j] enters boundary at cycle k+j, arrives at PE(0,j) at cycle k+j+1
# Both reach PE(i,j) at cycle k+i+j+1 (after pass-through delay)
# Last accumulation at PE(i,j): cycle (K-1)+i+j+1 = K+i+j

print("PE(i,j) | last_accum_cycle | en_high? (current) | en_high? (fixed)")
print("-" * 75)

for i in range(M):
    for j in range(N):
        last_accum = K + i + j  # K + i + j (with the +1 from pass-through)
        en_current = last_accum < FEED_CYCLES_CURRENT  # en is high during cycles 0..FEED_CYCLES-1
        en_fixed   = last_accum < FEED_CYCLES_FIXED
        status_cur = "✓" if en_current else "✗ MISSING"
        status_fix = "✓" if en_fixed   else "✗ MISSING"
        print(f"  PE({i},{j}) | cycle {last_accum:2d}          | {status_cur:16s} | {status_fix}")

print()
print("The bug: data enters boundary at cycle c, arrives at PE at cycle c+1,")
print("but en goes low at cycle FEED_CYCLES. So the last FEED cycle's data")
print("is never accumulated.")
print()
print(f"Fix: FEED_CYCLES = K + M + N - 2 = {FEED_CYCLES_FIXED}")
