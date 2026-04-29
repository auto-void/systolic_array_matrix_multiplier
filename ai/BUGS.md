# BUGS.md — Bug 追踪

优先级：🔴 高  🟡 中  🟢 低

> 记录所有已发现但未修复的 bug。修复并仿真通过后才能标记 ✅。

---

## 🔴 Bug 1：Testbench 数据设置时序偏移 1 周期

**文件**：`tb/tb_systolic_array.v` — `feed_matrices` task

**现象**：PE(0,0) 期望 30 得 29，所有 PE 都少累加约 1 个乘积。

**根因**：Testbench 在 `@(posedge clk)` **之后**才设置下一个周期的数据，但组合逻辑边界在同一 posedge 就读取了旧数据。数据永远比边界期望的晚 1 周期。

```verilog
// 当前代码：先等 posedge，再设数据 → 边界读到的是上一拍的旧值
for (c = 0; c < fc; c = c + 1) begin
    @(posedge clk);                          // ← 边界在这里读数据
    // Set data for cycle c+1               // ← 但数据在这里才更新！
    for (ii = 0; ii < M_ROWS; ii = ii + 1)
        if ((c+1) >= ii && ((c+1) - ii) < K_DIM)
            a_data[ii] = A[ii][(c+1) - ii];  // 太晚了
```

**修复**：在 `@(posedge clk)` **之前**设置当前周期的数据：

```verilog
// 先设数据，再等 posedge → 边界在 posedge 读到正确值
for (c = 0; c < fc; c = c + 1) begin
    // Set data for cycle c (before the edge!)
    for (ii = 0; ii < M_ROWS; ii = ii + 1)
        if (c >= ii && (c - ii) < K_DIM)
            a_data[ii] = A[ii][c - ii];
        else
            a_data[ii] = 0;
    for (jj = 0; jj < N_COLS; jj = jj + 1)
        if (c >= jj && (c - jj) < K_DIM)
            b_data[jj] = B[c - jj][jj];
        else
            b_data[jj] = 0;
    @(posedge clk);  // 边界在此读到刚设好的数据
end
```

**状态**：⬜ 待修复

**复现**：
```bash
make sim
# 观察输出：PE(0,0) = 29（期望 30），所有 PE 系统性偏小
```

---

## 🔴 Bug 2：`en` 信号延迟 1 周期，导致首个数据丢失

**文件**：`src/systolic_array.v`

**现象**：与 Bug 1 叠加后，PE(0,0) = 29（期望 30），丢失 `A[0][0]×B[0][0] = 1`。

**根因**：`en = (state == S_FEED)` 使用**当前状态**，而 `state` 通过 NBA 更新。FSM 在 posedge 4 进入 S_FEED，但 `en` 要到 posedge 5 才变高。边界在 posedge 4 读到了 cycle 0 数据，但 `en=0` 不累加；posedge 5 `en=1` 时边界已经读 cycle 1 数据了。

```
posedge 4: state→S_FEED(NBA), en=0, 边界读到 cycle 0 数据 → PE 不累加（丢失！）
posedge 5: state=S_FEED, en=1, 边界读到 cycle 1 数据 → PE 累积 4
```

**修复方案**（二选一）：
- **方案 A**（改 RTL）：`assign en = (state_next == S_FEED);` — 在状态转移的同一周期就使能
- **方案 B**（改 TB）：在进入 feed 循环前提前 1 周期设置 cycle 0 数据

**状态**：⬜ 待修复

**复现**：同 Bug 1（两者叠加），`make sim` 即可观察到。

---

## 🔴 Bug 3：Overflow Testbench 同样的时序竞态

**文件**：`tb/tb_overflow.v`

**现象**：期望 128 饱和到 127，实际只得到 64（只累加了 1 个 64）。

**根因**：与 Bug 1 相同——数据在 `@(posedge clk)` 之后才设置，边界读到上一拍的旧值。

```verilog
// 当前代码：先 @(posedge clk) 再设数据
for (c = 0; c < feed_cycles; c = c + 1) begin
    // 设数据...
    @(posedge clk);  // 边界在这里读到的是上一轮的旧数据
end
```

**修复**：同 Bug 1，改为先设数据再 `@(posedge clk)`。

**状态**：⬜ 待修复

**复现**：
```bash
make overflow
# 观察输出：C[i][j] = 64（期望 127 饱和），只累加了 1 个乘积
```

---

## 🟡 Bug 4：`$clog2(1)` = 0 导致零宽度端口

**文件**：`src/systolic_array.v`、`src/systolic_array_top.v`

**现象**：当 `M_ROWS=1` 或 `N_COLS=1` 时，`$clog2(1) = 0`，导致 `row_sel` 或 `col_sel` 端口位宽为 0。

```verilog
input  wire [$clog2(M_ROWS)-1:0] row_sel,   // $clog2(1)-1 = -1 → 位宽 0！
input  wire [$clog2(N_COLS)-1:0] col_sel,
```

**修复**：
```verilog
input  wire [($clog2(M_ROWS) > 0 ? $clog2(M_ROWS) : 1) - 1:0] row_sel,
input  wire [($clog2(N_COLS) > 0 ? $clog2(N_COLS) : 1) - 1:0] col_sel,
```

**状态**：⬜ 待修复

**复现**：
```bash
# 修改 tb_systolic_array.v 参数为 M_ROWS=1, N_COLS=1，然后：
make sim
# iverilog 报错：port size mismatch 或零宽度端口
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
