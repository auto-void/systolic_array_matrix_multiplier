// ============================================================================
// Common utilities for systolic_array project
// ============================================================================

// Safe address width: $clog2(N) = 0 when N = 1, so we clamp to at least 1 bit.
// This avoids zero-width ports that break synthesis/simulation for M_ROWS=1 or
// N_COLS=1 configurations.
`define ADDR_WIDTH(N) ($clog2(N) > 0 ? $clog2(N) : 1)
