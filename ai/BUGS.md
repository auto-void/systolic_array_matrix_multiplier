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

**状态**：✅ 已修复（2026-05-01）

**修复**：tb_overflow.v 使用 `` `ifdef `` 接收参数，Makefile 新增 `make neg_overflow`（K_DIM=4）目标。A=-8, B=7, 每个乘积 -56, K_DIM=4 求和 -224 < -128 触发负溢出饱和到 -128。

---

## 🟢 Bug 9：`check_result` Task 的 test_name 字符串编码问题

**文件**：`tb/tb_systolic_array.v` — `check_result` task

**现象**：Test 8 的输出显示为乱码 `��� PASSED`，因为 `check_result` 使用 `input [255:0]` 接收字符串，而 Test 8 直接用 `$display` 打印不经过 `check_result`。

**状态**：✅ 已修复（2026-05-01，Test 8 改用 ASCII `[PASS]` 显示）

---

## 🟢 Bug 10：`$dumpvar` 在非 trace 模式下产生 Info 警告

**文件**：`tb/tb_systolic_array.v`、`tb/tb_overflow.v`

**现象**：`make sim` 输出 `-Info: tb/tb_systolic_array.v:86: $dumpvar ignored, as Verilated without --trace`

**修复**（2026-05-01）：用 `` `ifdef DUMP `` 条件编译包裹 `$dumpfile/$dumpvars`，默认不输出波形。需要波形时 `make sim` 加 `-DDUMP` 或 Makefile 的 `wave` 目标。

**状态**：✅ 已修复（2026-05-01）

---

## 🟡 Bug 11：`clear_acc` 与 `en` 同时有效时的优先级隐患

**文件**：`src/pe.v` + `src/systolic_array.v`

**现象**：PE 中 `clear_acc` 优先级高于 `en`（`if (clear_acc) ... else if (en) ...`）。当前 `clear = (state==S_IDLE)||(state==S_DONE)`，FEED 状态下 clear_acc=0，所以不会触发。但这个安全性依赖于 FSM 的隐式语义——如果未来修改 FSM 去掉 DONE 状态的 clear，首拍数据就会被丢弃。

**根因**：`en = (state == S_FEED)` 是组合逻辑，在同一 posedge 与 state 的 NBA 更新同时生效。IDLE→FEED 转换时 en 在第一个 FEED posedge 读到旧状态（IDLE），所以 en=0 不累加——这恰好是正确行为（边界数据需要一拍延迟）。但这个"正确"是巧合，不是显式设计。

**状态**：⬜ 未修复（设计隐患，当前不触发）

**建议**：将 `en` 改为寄存器输出（`en_d1 = (state_next == S_FEED)`），显式声明时序意图，消除隐式依赖。

---

## 🟡 Bug 12：`en` 信号组合逻辑依赖 FSM 状态 NBA 更新时序

**文件**：`src/systolic_array.v`

```verilog
.en(state == S_FEED),  // 组合逻辑比较
```

**现象**：`state` 通过 NBA 更新，`en` 在同一 posedge 的组合求值阶段读到的是旧 state。IDLE→FEED 转换的 posedge：en 读到 IDLE → en=0；下一个 posedge：en 读到 FEED → en=1。

这是正确行为（与边界数据延迟一拍匹配），但依赖 Verilog 事件调度的隐式语义，而非显式寄存器延迟。如果有人改了边界逻辑的时序（比如去掉组合逻辑改为寄存器），整个数据对齐就会出错。

**状态**：⬜ 未修复（与 Bug 11 同源，建议一并修复）

**建议**：同 Bug 11——改用寄存器版 `en`。

---

## 🟡 Bug 13：`feed_matrices` task 额外一拍导致无法测试真正的 DONE→FEED back-to-back

**文件**：`tb/tb_systolic_array.v`、`tb/tb_overflow.v` — `feed_matrices` task

**现象**：task 末尾在 deassert valid 之前多了一拍 `@(posedge clk)`：

```verilog
for (ii...) a_data[ii] = 0;
for (jj...) b_data[jj] = 0;
@(posedge clk);    // ← 这一拍让 FSM 从 DRAIN 进 DONE 再回 IDLE
a_valid = 0;
b_valid = 0;
```

这导致 `wait(!busy)` 时 FSM 已在 IDLE，Test 6 (back-to-back) 测试的是 IDLE→FEED，不是 DONE→FEED。真正的 back-to-back 场景（DONE 直接到 FEED，无 IDLE 间隙）从未被 tb_systolic_array 验证。

**验证**：`tb_bug_verify` 的 BUG TEST 1 单独实现了 DONE→FEED 测试，但 `tb_systolic_array` 的 Test 6 没有。

**状态**：⬜ 未修复

**建议**：在 `feed_matrices` 末尾去掉 `a_valid=0; b_valid=0`，让调用者控制何时 deassert valid。或新增一个 `feed_matrices_backto_back` task 不加额外那拍。

---

## 🟢 Bug 14：`check_result` 误报 PASSED

**文件**：`tb/tb_systolic_array.v` — `check_result` task

**现象**：`errors` 是全局累计变量。如果 Test 1 失败（errors=1），Test 2 的 `check_result` 会打印 `→ FAILED`——但这不是因为 Test 2 自己失败，而是读到了 Test 1 留下的 error count。反之，如果 Test 1 PASS 但 Test 2 FAIL，Test 1 打印 `→ PASSED` 是对的，但 Test 2 打印 `→ FAILED` 时无法区分是自己失败还是之前的。

```verilog
if (errors == 0) $display("  → PASSED");  // ← 检查全局 errors，不是本次
else             $display("  → FAILED");
```

**状态**：⬜ 未修复

**建议**：在 task 开头记录 `errors_before = errors`，结尾检查 `errors == errors_before`。

---

## 🟢 Bug 15：`check_result` 的 test_name 截断（Bug 9 关联）

**文件**：`tb/tb_systolic_array.v`

**现象**：`input [255:0] test_name` 只有 32 字节，超过 32 字符的名字会被截断。Test 8 绕过 `check_result` 直接用 `$display` 就是这个原因。

**状态**：✅ 已规避（2026-05-01，Test 8 改用直接打印），根本原因未修复。

---

## 🟢 Bug 16：`tb_bug_verify` 随机范围检查用 8-bit 硬编码

**文件**：`tb/tb_bug_verify.v` — BUG TEST 2

**现象**：

```verilog
if (val == 127) saw_max = 1;  // ← 硬编码 127
```

DATA_WIDTH=8 时正确，但参数化后检查失效。

**状态**：⬜ 未修复

**建议**：改为 `if (val == (1 << (DATA_WIDTH-1)) - 1) saw_max = 1;`

---

## 🟡 Bug 17：`overflow_count` 组合逻辑在计算过程中可能毛刺

**文件**：`src/systolic_array.v`

**现象**：`overflow_count` 是组合逻辑（`always @(*)` 求和所有 PE 的 overflow flag）。在 FEED 阶段，PE 逐周期累加，某些 PE 可能在中间周期溢出，overflow_count 在每个周期都会变化。最终值只在计算结束后稳定，但中间值不可靠。

```verilog
always @(*) begin
    ovf_cnt = 0;
    for (oi...) for (oj...)
        ovf_cnt = ovf_cnt + 8'(pe_overflow[oi][oj]);
end
```

**状态**：⬜ 未修复

**建议**：改为寄存器输出，在 c_valid 时锁存最终值。或增加 `overflow_count_valid` 信号指示何时可读。

---

## 🟢 Bug 18：`cycle_count` 在 back-to-back 场景不重置

**文件**：`src/systolic_array.v`

**现象**：cycle_count 只在 IDLE→FEED 时清零。DONE→FEED（back-to-back）不清零，cycle_count 会累计两轮计算的总周期。

```verilog
else if (state == S_IDLE && state_next == S_FEED)
    cyc_cnt <= 0;
```

**状态**：⬜ 未修复（行为可接受，但语义不明确）

**建议**：DONE→FEED 时也清零，或增加 `cycle_count_valid` 信号在 c_valid 时锁存。

---

## 🟡 Bug 19：`c_data` 二维 unpacked array 端口综合兼容性差

**文件**：`src/systolic_array.v`、`src/systolic_array_top.v`

**现象**：

```verilog
output wire signed [ACCUM_WIDTH-1:0] c_data [0:M_ROWS-1][0:N_COLS-1],
```

Vivado 对 unpacked array 端口支持差，综合时可能报错或生成不可预期的网表。

**状态**：⬜ 未修复（TODO #13 已标记）

**建议**：去掉 c_data 端口，只保留 result_bank + row_sel/col_sel 地址读出。或改为一维 flatten 输出。

---

## 🟢 Bug 20：`make wave` 每次都重新编译

**文件**：`Makefile`

**现象**：`wave` 目标直接编译到 `$(SIM_DIR)`，与 `sim` 共享 build dir。每次切换 `--trace` 开关都要重新编译。

**状态**：⬜ 未修复

**建议**：`wave` 目标单独用 `$(BUILD)/wave` 目录。

---

## 🟢 Bug 21：`neg_overflow` 测试未纳入 `all` 目标

**文件**：`Makefile`

**现象**：`make all: sim` 只跑主仿真，不跑 `overflow` / `neg_overflow`。

**状态**：⬜ 未修复

**建议**：`all: sim overflow neg_overflow` 或新增 `make test` 跑全部。

---

## 备注

- **Bug 1+2 叠加**是当前所有仿真失败的根因（已修复）
- **Bug 6** 是新发现的 RTL 设计缺陷，影响真正的 back-to-back 场景（已修复）
- **Bug 11/12** 是 en 信号设计隐患，当前不触发但脆弱
- **Bug 13** 是测试覆盖盲区，真正的 DONE→FEED back-to-back 未被 tb_systolic_array 验证
- Bug 7-10 已修复，Bug 14-21 为新发现
