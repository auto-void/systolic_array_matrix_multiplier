# BUGS.md — Bug 追踪

优先级：🔴 高  🟡 中  🟢 低

> 记录所有已发现但未修复的 bug。修复并仿真通过后才能标记 ✅。

---

## 🔴 Bug 1：Testbench 数据设置时序偏移 1 周期

**文件**：`tb/tb_systolic_array.v` — `feed_matrices` task

**现象**：PE(0,0) 期望 30 得 29，所有 PE 都少累加约 1 个乘积。

**根因**：Testbench 在拉高 valid 之后等 posedge（FSM 进 FEED），此时 state=IDLE，边界输出 0；data 在 posedge 之后才设置，但那时候 TB 已经进入下一个循环步骤，导致每拍数据都错位 1 周期。

**修复**（2026-04-30）：
- `wait(!busy)` 后加一个 `@(posedge clk)` 确保 FSM 在 IDLE
- 然后拉高 valid，`@(posedge clk)`（FSM 进 FEED，feed_cnt=0）
- posedge 之后立刻设 cycle-0 数据（Verilator 在同一时间步内 initial block 先于 always 完成，组合逻辑立刻更新）
- 循环体：设 cycle-c 数据 → `@(posedge clk)`，共 fc 次

**状态**：✅ 已修复（2026-04-30）

---

## 🔴 Bug 2：`en` 信号延迟 1 周期，导致首个数据丢失

**文件**：`src/systolic_array.v`

**现象**：与 Bug 1 叠加后，PE(0,0) = 29（期望 30），丢失 `A[0][0]×B[0][0] = 1`。

**根因**：`en = (state == S_FEED)` 使用**当前状态**，而 `state` 通过 NBA 更新。FSM 在 posedge 4 进入 S_FEED，但 `en` 要到 posedge 5 才变高。边界在 posedge 4 读到了 cycle 0 数据，但 `en=0` 不累加；posedge 5 `en=1` 时边界已经读 cycle 1 数据了。

```
posedge 4: state→S_FEED(NBA), en=0, 边界读到 cycle 0 数据 → PE 不累加（丢失！）
posedge 5: state=S_FEED, en=1, 边界读到 cycle 1 数据 → PE 累积 4
```

**状态**：✅ 已通过 TB 修复间接解决（2026-04-30）
- Bug 1 的修复方案（valid 拉高后多等一拍再进 FEED 循环）同时规避了此问题
- en 信号本身保持 `state == S_FEED`（RTL 未改动）

**复现**：同 Bug 1（两者叠加），`make sim` 即可观察到。

---

## 🔴 Bug 3：Overflow Testbench 同样的时序竞态

**文件**：`tb/tb_overflow.v`

**现象**：期望 128 饱和到 127，实际只得到 64（只累加了 1 个 64）。

**根因**：与 Bug 1 相同——数据在 `@(posedge clk)` 之后才设置，边界读到上一拍的旧值。

**修复**（2026-04-30）：采用与 Bug 1 相同的协议——拉高 valid，@posedge（FSM 进 FEED），之后在循环里设 cycle-c 数据 → @posedge。

**状态**：✅ 已修复（2026-04-30）

**验证**：`make overflow` 输出 `*** ALL OVERFLOW TESTS PASSED ***`

---

## 🟡 Bug 4：`$clog2(1)` = 0 导致零宽度端口

**文件**：`src/systolic_array.v`、`src/systolic_array_top.v`、`tb/tb_systolic_array.v`、`tb/tb_overflow.v`

**现象**：当 `M_ROWS=1` 或 `N_COLS=1` 时，`$clog2(1) = 0`，导致 `row_sel` 或 `col_sel` 端口位宽为 0，编译报错。

```verilog
input  wire [$clog2(M_ROWS)-1:0] row_sel,   // $clog2(1)-1 = -1 → 位宽 0！
input  wire [$clog2(N_COLS)-1:0] col_sel,
```

**修复**（2026-04-30）：创建 `src/utils.vh` 工具头文件，统一使用 `ADDR_WIDTH` 宏：

```verilog
// src/utils.vh
`define ADDR_WIDTH(N) ($clog2(N) > 0 ? $clog2(N) : 1)
```

```verilog
// systolic_array.v / systolic_array_top.v / TB
input  wire [`ADDR_WIDTH(M_ROWS)-1:0] row_sel,
input  wire [`ADDR_WIDTH(N_COLS)-1:0] col_sel,
```

**状态**：✅ 已修复（2026-04-30）

**验证**：`make sim M=1 K=4 N=1` → `*** ALL TESTS PASSED ***`

**复现**（修复前）：
```bash
make sim M=1 K=4 N=1
# 报错：零宽度端口或位宽不匹配
```

---

## 🟢 Bug 5：DESIGN.md 注释与实际代码不一致

**文件**：`src/systolic_array.v` 第 82-84 行注释

```
// Total FEED cycles = K_DIM + max(M_ROWS, N_COLS) - 1   ← 旧公式，已过时
```

实际代码已改为 `FEED_CYCLES = K_DIM + M_ROWS + N_COLS - 2`，但注释还写着旧的 `K+max(M,N)-1`。

**修复**：更新注释匹配代码。

**状态**：✅ 已修复（2026-04-29，注释改为 `K_DIM + M_ROWS + N_COLS - 2`）

**复现**：`grep "max(M_ROWS, N_COLS)" src/systolic_array.v` — 应该找不到匹配（旧注释已删）。

---

## 备注

- **Bug 1+2 叠加**是当前所有仿真失败的根因
- Bug 1 和 Bug 2 可以独立修复，也可以一起修
- Bug 4 只影响 M=1 或 N=1 的极端情况
