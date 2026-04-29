#!/usr/bin/env python3
"""
Verify FEED_CYCLES fix works for all matrix sizes.
"""

def test_size(M, K, N):
    FEED_CYCLES = K + M + N - 2
    A = [[i + k + 1 for k in range(K)] for i in range(M)]
    B = [[k + j + 1 for j in range(N)] for k in range(K)]
    expected = [[sum(A[i][k] * B[k][j] for k in range(K)) for j in range(N)] for i in range(M)]

    # Simulate PE array
    accum = [[0]*N for _ in range(M)]
    a_pipe = [[0]*N for _ in range(M)]  # pass-through register
    b_pipe = [[0]*N for _ in range(M)]

    for c in range(FEED_CYCLES):
        # Boundary inputs
        pe_a = [[0]*N for _ in range(M)]
        pe_b = [[0]*N for _ in range(M)]
        for i in range(M):
            if c >= i and (c - i) < K:
                pe_a[i][0] = A[i][c - i]
        for j in range(N):
            if c >= j and (c - j) < K:
                pe_b[0][j] = B[c - j][j]
        # Internal wiring
        for i in range(M):
            for j in range(N):
                if j > 0: pe_a[i][j] = a_pipe[i][j-1]
                if i > 0: pe_b[i][j] = b_pipe[i-1][j]
        # Accumulate + pass-through
        for i in range(M):
            for j in range(N):
                accum[i][j] += pe_a[i][j] * pe_b[i][j]
                a_pipe[i][j] = pe_a[i][j]
                b_pipe[i][j] = pe_b[i][j]

    # Check
    ok = True
    for i in range(M):
        for j in range(N):
            if accum[i][j] != expected[i][j]:
                ok = False
                return False, f"  PE({i},{j}): expected={expected[i][j]}, got={accum[i][j]}"
    return True, ""

print("Testing FEED_CYCLES = K + M + N - 2")
print("=" * 50)

sizes = [
    (1, 1, 1), (2, 2, 2), (3, 3, 3), (4, 4, 4),
    (2, 3, 4), (3, 5, 7), (4, 2, 4), (1, 4, 1),
    (8, 8, 8), (2, 8, 2), (8, 2, 8),
]

all_ok = True
for M, K, N in sizes:
    ok, msg = test_size(M, K, N)
    fc = K + M + N - 2
    status = "✓" if ok else "✗"
    print(f"  {status} M={M} K={K} N={N}  FEED_CYCLES={fc:2d}  {'PASS' if ok else 'FAIL'}")
    if not ok:
        all_ok = False
        print(msg)

print()
if all_ok:
    print("ALL SIZES PASS ✓")
else:
    print("FAILURES DETECTED ✗")
