# BUGS.md — Bug 追踪

优先级：🔴 高  🟡 中  🟢 低

> 记录所有已发现但未修复的 bug。修复并仿真通过后才能标记 ✅。

---

## 🔴 Bug 1：Testbench 数据设置时序偏移 1 周期

**文件**：`tb/tb_systolic_array.v` — `feed_matrices` task

**现象**：PE(0,0) 期望 30 得 29，所有 PE 都少累加约 1 个乘积。

**根因**：Testbench 在拉高 valid 之后等 posedge（FSM 进 FEED），此时 state=IDLE，边界输出 0；data 在 posedge 之后才设置，但那时候 TB 已经进入下一个循环步骤，导致每拍数据都错位 1 周期。

**修复**（2026-04-30，2026-05-01 更新）：
- 数据在 `@(posedge clk)` **之前**设置（先设 cycle-0 数据再 assert valid，循环从 c=1 开始）
- 确保边界组合逻辑在 posedge 时已有正确值，消除 Verilator 事件调度竞态

**状态**：✅ 已修复（2026-04-30，2026-05-01 协议统一更新）

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

## 🔴 Bug 6：Back-to-back DONE→FEED 跳过 IDLE 时累加器未清零

**文件**：`src/systolic_array.v` — FSM + `clear_acc` 逻辑

**现象**：FSM 从 DONE 直接跳到 FEED（`a_valid&&b_valid` 在 DONE 状态立刻断言），第二轮计算结果异常。

**根因**：原 `clear` 信号包含 `prev_state==S_DONE && state==S_FEED` 条件，导致 DONE→FEED 转换时 `clear_acc` 和 `en` 同一拍为高。PE 中 `clear_acc` 优先级高于 `en`，第一拍数据被丢弃。同时 TB 在 posedge 之后才设 cycle-0 数据，边界在 clear 生效时读到零值。

**修复**（2026-05-01）：
- **RTL**：去掉 `prev_state==S_DONE && state==S_FEED` 条件，`clear` 仅在 `state==S_IDLE || state==S_DONE` 时为高。DONE 状态本身保持 `clear_acc` 高，累加器在 DONE 期间已被清零。
- **TB**：所有 testbench 改为在 posedge **之前**设置 cycle-0 数据（先设数据再 assert valid 或在循环开始前预设），确保边界组合逻辑在 FSM 进入 FEED 时已有正确值。
- **tb_bug_verify.v**：修正 A2×B2 期望值（C2=[[70,100],[150,220]]，原错误写为 [[70,80],[150,180]]）

**状态**：✅ 已修复（2026-05-01）

**验证**：
```
make sim                  → *** ALL TESTS PASSED *** (9 tests)
make sim M=8 K=8 N=8    → *** ALL TESTS PASSED ***
make sim M=3 K=5 N=7    → *** ALL TESTS PASSED ***
make sim W=16            → *** ALL TESTS PASSED ***
make sim M=1 K=4 N=1    → *** ALL TESTS PASSED ***
make sim M=1 K=1 N=1    → *** ALL TESTS PASSED ***
make overflow            → *** ALL OVERFLOW TESTS PASSED ***
tb_bug_verify Bug 1      → ✓ Back-to-back results are clean
```

---

## 🟡 Bug 7：Testbench 随机值范围错误，永远不生成 127

**文件**：`tb/tb_systolic_array.v` — Test 2 随机值生成

**现象**：`$urandom_range(0, 2**DATA_WIDTH - 2) - (2**(DATA_WIDTH-1))` 的范围是 -128..126，永远不生成 127（8-bit signed 的最大值）。

**根因**：`$urandom_range(0, 254)` 的上界是 254 而非 255，减去 128 后最大值为 126。

**状态**：✅ 已修复（2026-04-30，commit 8ed2209，随 Bug 6 一起修复）

---

## 🟡 Bug 8：Overflow TB 缺少负溢出饱和测试

**文件**：`tb/tb_overflow.v`

**现象**：只测试了正溢出饱和（`128 → 127`），负溢出测试被跳过。当前参数 `DATA_WIDTH=4, K_DIM=2, ACCUM_WIDTH=8` 下，`(-8)*7*2 = -112` 不会触发负溢出（`-112 > -128`）。

**状态**：🟡 未修复

**修复建议**：增加负溢出测试用例，使用更极端的参数：
- 方案 A：`DATA_WIDTH=8, K_DIM=2, ACCUM_WIDTH=8`，用 `-128*127*2 = -32512` 远超 `-128`
- 方案 B：`DATA_WIDTH=4, K_DIM=4, ACCUM_WIDTH=8`，用 `7*7*4 = 196 > 127` 测正溢出，`(-8)*7*4 = -224 < -128` 测负溢出

---

## 🟢 Bug 9：`check_result` Task 的 test_name 字符串编码问题

**文件**：`tb/tb_systolic_array.v` — `check_result` task

**现象**：Test 8 的输出显示为乱码 `��� PASSED`，因为 `check_result` 使用 `input [255:0]` 接收字符串，而 Test 8 直接用 `$display` 打印不经过 `check_result`。

**状态**：🟢 未修复（仅影响显示，不影响功能验证）

**修复**：将 `check_result` 的 `test_name` 参数改为 `input [8*32-1:0]`（256-bit ASCII），或改用 `string` 类型（SystemVerilog）。

---

## 🟢 Bug 10：`$dumpvar` 在非 trace 模式下产生 Info 警告

**文件**：`tb/tb_systolic_array.v`、`tb/tb_overflow.v`

**现象**：`make sim` 输出 `-Info: tb/tb_systolic_array.v:86: $dumpvar ignored, as Verilated without --trace`

**状态**：🟢 未修复（仅影响输出整洁度）

**修复建议**：
- 方案 A：用 `` `ifdef DUMP `` 条件编译包裹 `$dumpfile/$dumpvars`
- 方案 B：Makefile 的 `sim` 目标默认加 `--trace`（增加编译时间和二进制大小）
- 方案 C：忽略（不影响功能）

---

## 备注

- **Bug 1+2 叠加**是当前所有仿真失败的根因（已修复）
- **Bug 6** 是新发现的 RTL 设计缺陷，影响真正的 back-to-back 场景
- Bug 7/8 是测试覆盖不足，不影响 RTL 正确性
- Bug 9/10 是 cosmetic 问题
