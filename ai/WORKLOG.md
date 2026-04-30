# WORKLOG.md — AI 工作日志

每次 AI 修改代码时，必须在此文件**顶部**添加一条记录。

**职责**：只记录"做了什么"和"验证结果"。
- 设计决策 → `ai/DESIGN.md`
- Bug 状态 → `ai/BUGS.md`
- 待办事项 → `ai/TODO.md`

格式：
```
## [日期] AI名称 — 简要描述

### 修改内容
- 具体修改了哪些文件、做了什么改动

### 验证结果（必须有）
- 跑了哪些测试、结果如何
```

### 验证
- 运行了哪些测试
- 结果如何

### 已知问题
- 发现但未修复的问题
```

---

## [2026-05-01] — 修复 Bug 13/14/16/17/18/20/21

### 修改内容

**src/systolic_array.v — Bug 17/18 修复**
- Bug 17：`overflow_count` 从组合逻辑改为寄存器输出，在 `c_valid` 时锁存最终值，消除计算过程中毛刺
- Bug 18：`cycle_count` 清零条件从 `state==S_IDLE && state_next==S_FEED` 改为 `state_next==S_FEED && state!=S_FEED`，DONE→FEED 时也会重置
- `any_overflow` 也改为寄存器输出，在 `c_valid` 时锁存，IDLE 时清零

**tb/tb_systolic_array.v — Bug 13/14 修复**
- Bug 13：`feed_matrices` task 末尾去掉 `a_valid=0; b_valid=0` 和多余的 `@(posedge clk)`，task 只负责喂数据，由调用者控制 valid 和等待结果
- Bug 14：`check_result` task 改用 `errors_before` 局部变量，只检查本次比较是否产生新 error
- Test 6b 重写为真正的 DONE→FEED back-to-back：valid 保持高电平，预设 cycle-0 数据后直接进入下一轮 FEED

**tb/tb_overflow.v — 协议统一**
- 同步 feed_matrices 协议：去掉末尾多余 posedge，valid 由调用者控制

**tb/tb_bug_verify.v — Bug 16 修复**
- 随机范围检查从硬编码 `127` 改为 `(1 << (DATA_WIDTH-1)) - 1`

**Makefile — Bug 20/21 修复**
- Bug 20：`wave` 目标使用独立 build dir `$(BUILD)/wave`，不再覆盖 `sim` 的编译产物
- Bug 21：`all` 目标从 `sim` 改为 `sim overflow`

### 验证结果

⚠️ 未仿真验证（环境无 verilator）。所有修改基于逻辑推演，需在有 verilator 的环境跑：
```
make sim
make sim M=8 K=8 N=8
make sim M=3 K=5 N=7
make sim W=16
make overflow
make neg_overflow
```

### 关键设计决策

1. **overflow_count 改为寄存器**：在 c_valid 时锁存最终值，避免 FEED 阶段的毛刺。代价：中间周期读到的是上一轮的值，对功能无影响。
2. **feed_matrices 去掉 valid 控制**：让调用者决定何时 deassert valid，支持 back-to-back 测试模式。
3. **en 信号保持组合逻辑**（Bug 11/12 不修）：改用寄存器 en 会改变累加时序，需要同步调整 FEED_CYCLES 和边界逻辑，改动范围太大，当前行为正确且有明确的时序依赖文档。

---

## [2026-05-01] — 全代码审查：发现 Bug 11-21

### 修改内容

**ai/BUGS.md** — 新增 Bug 11-21

RTL 设计隐患：
- Bug 11：🟡 `clear_acc` 与 `en` 同时有效时的优先级隐患（当前不触发但脆弱）
- Bug 12：🟡 `en` 信号组合逻辑依赖 FSM 状态 NBA 更新时序（隐式时序依赖）

Testbench 问题：
- Bug 13：🟡 `feed_matrices` task 额外一拍导致无法测试真正的 DONE→FEED back-to-back
- Bug 14：🟢 `check_result` 误报 PASSED（全局 errors 累计导致）
- Bug 15：🟢 `check_result` test_name 截断（Bug 9 关联，已规避）
- Bug 16：🟢 `tb_bug_verify` 随机范围检查 8-bit 硬编码

RTL 设计隐患：
- Bug 17：🟡 `overflow_count` 组合逻辑计算过程中毛刺
- Bug 18：🟢 `cycle_count` back-to-back 场景不重置
- Bug 19：🟡 `c_data` 二维 unpacked array 端口综合兼容性差

工程问题：
- Bug 20：🟢 `make wave` 每次都重新编译
- Bug 21：🟢 `neg_overflow` 测试未纳入 `all` 目标

### 验证结果

- 审查范围：src/pe.v、src/systolic_array.v、src/systolic_array_top.v、src/utils.vh、tb/tb_systolic_array.v、tb/tb_overflow.v、tb/tb_bug_verify.v、tb/tb_bug_hunt.v、Makefile、scripts/*.py
- RTL 核心逻辑确认正确：错开喂入、PE 累加、FSM 转换、溢出饱和、result_bank 锁存、c_valid 时序
- 所有已知仿真仍然 PASS（未改 RTL/TB 代码）

### 关键发现

1. **en 信号的隐式正确性**：`en = (state == S_FEED)` 在 IDLE→FEED 转换时读到旧状态（en=0），恰好与边界数据延迟一拍匹配。这是巧合而非设计，未来修改 FSM 时极易破坏。
2. **back-to-back 测试覆盖盲区**：tb_systolic_array 的 Test 6 因 feed_matrices 额外一拍，实际测试的是 IDLE→FEED，不是 DONE→FEED。只有 tb_bug_verify 的 BUG TEST 1 覆盖了真正的 back-to-back。
3. **c_valid 采样时序正确**：TB 在 `wait(c_valid); @(posedge clk)` 时，c_data 在 @(posedge clk) 的 NBA 更新前仍保持有效值（accum 尚未被 clear_acc 清零），golden_C 正确捕获结果。

---

## [2026-05-01] — 修复 TB 时序竞态 + Bug 6 DONE→FEED clear_acc，全测试通过

### 修改内容

**核心问题**：Verilator 5.020 事件调度中，initial block 在 `@(posedge clk)` 之后设置 `a_data`，但组合逻辑边界在同一时间步不重新求值，导致数据总是晚 1 拍被 PE 看到。

**tb/tb_systolic_array.v — feed_matrices 协议重写**
- 改为"数据在 posedge 之前设置"协议：先预设 cycle-0 数据，再 assert valid，再 `@(posedge clk)` 进 FEED
- 循环从 c=1 开始（cycle-0 已预设），每次设 cycle-c 数据 → `@(posedge clk)`
- 最后多一拍 posedge 让 PE 累加最后一个 cycle 的数据
- 删除 debug 临时代码

**tb/tb_overflow.v — 同样的协议修复**
- 预设 cycle-0 数据（-8）后再 assert valid
- 循环从 c=1 开始

**tb/tb_bug_verify.v — 协议修复 + 期望值修正**
- 三个 feed 段全部改为"先设数据再 posedge"协议
- 修正 A2×B2 期望值：C2=[[70,100],[150,220]]（原错误写为 [[70,80],[150,180]]）

**src/systolic_array.v — Bug 6 修复**
- `clear` 信号去掉 `prev_state==S_DONE && state==S_FEED` 条件
- 仅在 `state==S_IDLE || state==S_DONE` 时为高
- DONE 状态本身保持 clear_acc 高多个周期，累加器在进入 FEED 前已被清零
- TB 在 DONE 状态预设 cycle-0 数据，边界在 FEED 第一拍就有正确值

### 验证结果

```
make sim                  → *** ALL TESTS PASSED *** (9 tests)
make sim M=8 K=8 N=8    → *** ALL TESTS PASSED ***
make sim M=3 K=5 N=7    → *** ALL TESTS PASSED ***
make sim W=16            → *** ALL TESTS PASSED ***
make sim M=1 K=4 N=1    → *** ALL TESTS PASSED ***
make sim M=1 K=1 N=1    → *** ALL TESTS PASSED ***
make overflow            → *** ALL OVERFLOW TESTS PASSED ***
tb_bug_verify Bug 1      → ✓ Back-to-back results are clean (no contamination)
tb_bug_verify Bug 3      → ✓ Negative multiplication correct
tb_bug_verify Bug 4      → ✓ result_bank preserves value correctly
```

### 关键发现

Verilator 5.020 的 `initial` block 在 `@(posedge clk)` 之后恢复执行时，组合逻辑（`assign`）不会在同一时间步重新求值。这与 WORKLOG 2026-04-30 中记录的行为不同（当时 Verilator 可能是不同版本或编译选项）。解决方案：**数据必须在 `@(posedge clk)` 之前设置**，确保组合逻辑在 posedge 时已有正确值。

---

### 修改内容

**ai/BUGS.md** — 新增 Bug 6-10
- Bug 6：🔴 Back-to-back DONE→FEED 跳过 IDLE 时累加器未清零（RTL 设计缺陷）
- Bug 7：🟡 TB 随机值范围错误，永远不生成 127
- Bug 8：🟡 Overflow TB 缺少负溢出饱和测试
- Bug 9：🟢 check_result test_name 字符串编码乱码
- Bug 10：🟢 $dumpvar 非 trace 模式下产生 Info 警告

**tb/tb_bug_verify.v** — 新增 bug 验证测试平台
- Bug 6 验证：back-to-back DONE→FEED 不经 IDLE，第二轮结果异常
- Bug 7 验证：随机值范围分析，确认 127 从未生成
- Bug 3 验证：负数乘法正确性
- Bug 4 验证：c_data vs result_bank 在 DONE 状态后的行为

### 验证结果

```
Bug 6 仿真输出：
  Result 2: C[0][0]=0 (expect 70), C[0][1]=0 (expect 80)
  ✗ BUG CONFIRMED: Back-to-back contamination!

Bug 7 仿真输出：
  ✗ BUG: $urandom_range(0,254)-128 never generates 127

Bug 3 验证：负数乘法正确 ✓
Bug 4 验证：result_bank 保持正确值 ✓
```

### 关键发现

1. **Bug 6 是唯一的 RTL 设计缺陷**：`clear_acc` 在 DONE→FEED 直接转换时不保证有效，需要在 FSM 层面修复。当前 TB 通过 `wait(!busy); @(posedge clk);` 规避，但真正的 back-to-back master 会触发。

2. **Bug 7 是测试覆盖盲区**：随机测试从不生成 DATA_WIDTH 范围的最大值（127），可能漏掉边界 case。

---

## [2026-04-30] — 修复 Bug 1/2/3，仿真全部 PASS，切换至 Verilator

### 修改内容

**tb/tb_systolic_array.v — `feed_matrices` task 时序修复（Bug 1）**
- 根因：TB 在 posedge 之后设数据，但 posedge 时 FSM 还在 IDLE，边界 guard 条件 `state==S_FEED` 为 false，pe_a_in=0
- 新协议：`wait(!busy)` → `@(posedge clk)`（确保在 IDLE）→ 拉高 valid → `@(posedge clk)`（FSM 进 FEED，initial block 在同时间步设 cycle-0 数据，组合逻辑立刻更新）→ 循环 c=0..fc-1：设 cycle-c 数据 → `@(posedge clk)`
- 同时修复 back-to-back bug：`wait(!busy)` 后加 `@(posedge clk)` 确保 FSM 从 DONE 退到 IDLE，避免 clear_acc 竞态

**tb/tb_overflow.v — 同样的协议修复（Bug 3）**
- 采用与 tb_systolic_array.v 相同的 valid/feed 时序

**Makefile — 从 iverilog 迁移到 Verilator**
- 使用 `verilator --binary -j 0 --timing -Wno-fatal` 模式
- `make sim`、`make overflow` 命令保持兼容

**src/utils.vh — 新建工具头文件（Bug 4）**
- 定义 `ADDR_WIDTH(N) = ($clog2(N) > 0 ? $clog2(N) : 1)` 宏，替换所有 `$clog2(M_ROWS/N_COLS)-1:0` 声明

**src/systolic_array.v — 警告消除**
- `ovf_cnt = ovf_cnt + 8'(pe_overflow[oi][oj])` 消除 WIDTHEXPAND 警告
- genvar 比较处添加 `/* verilator lint_off UNSIGNED */`

**tb/tb_systolic_array.v — 警告消除 + 新增边界测试**
- 数据赋值全部加 `DATA_WIDTH'(...)` 显式转换，消除 WIDTHTRUNC 警告
- 新增 Test 7（全零矩阵）、Test 8（1×1×1 最小尺寸）

**ai/BUGS.md** — Bug 4 状态更新为 ✅ 已修复
**ai/TODO.md** — W=16 测试、边界值测试、Bug 4 全部标记 ✅

### 验证结果

```
make sim                  → *** ALL TESTS PASSED *** (8 tests: 1-8)
make sim M=8 K=8 N=8    → *** ALL TESTS PASSED ***
make sim M=3 K=5 N=7    → *** ALL TESTS PASSED ***
make sim M=1 K=4 N=1    → *** ALL TESTS PASSED *** (M=1 边界，Bug 4 修复验证)
make sim W=16            → *** ALL TESTS PASSED *** (16-bit, zero warnings)
make sim M=1 K=1 N=1    → *** ALL TESTS PASSED *** (1×1×1 最小尺寸)
make overflow            → *** ALL OVERFLOW TESTS PASSED ***
```

8 个测试全部通过，Verilator 零警告。

### 关键发现（Verilator 调度语义）

Verilator `initial` block 在 `@(posedge clk)` 之后恢复执行时，与 `always @(posedge clk)` 的 NBA 更新处于同一时间步：
- `always @(posedge clk)` 先更新 state（NBA）
- `initial` block 恢复，设置 a_data，组合逻辑立刻重算 pe_a_in
- 这意味着"valid 拉高 → posedge → 设数据"的协议可以工作，因为数据在同一时间步的组合再求值中生效

---

## [2026-04-29] MiMo — 全面代码审查：发现 5 个 bug

### 修改内容
- **ai/BUGS.md** — 新建 bug 追踪文件，记录 5 个已发现的 bug

### 发现的 Bug

1. 🔴 **Testbench 数据设置时序偏移** (`tb_systolic_array.v`)
   - 数据在 `@(posedge clk)` 之后设置，组合逻辑边界读到旧值
   - 导致所有 PE 结果偏小，PE(0,0)=29 vs 期望 30

2. 🔴 **`en` 信号延迟 1 周期** (`systolic_array.v`)
   - `en = (state == S_FEED)` 使用当前状态，NBA 更新导致比状态转移晚 1 拍
   - 首个周期数据被边界读到但 PE 不累加

3. 🔴 **Overflow TB 同样的时序竞态** (`tb_overflow.v`)
   - 与 Bug 1 相同模式，期望 128 饱和到 127，实际只得到 64

4. 🟡 **`$clog2(1)=0` 零宽度端口** (`systolic_array.v`)
   - M_ROWS=1 或 N_COLS=1 时端口位宽为 0

5. 🟢 **注释过时** (`systolic_array.v`)
   - FEED_CYCLES 注释仍写旧公式 `K+max(M,N)-1`

### 根因分析
- Bug 1+2 叠加是所有仿真失败的根因
- Bug 1：testbench 数据晚 1 周期 → 边界读到上一拍数据
- Bug 2：en 信号晚 1 周期 → 首数据丢失
- 两者叠加：丢失 A[0][0]×B[0][0]=1，且每个 PE 都少累加约 1 个乘积

---

## [2026-04-29] MiMo — 修复 FEED_CYCLES 不足导致数据对齐 1-cycle offset bug

### 问题

所有测试中，右下区域 PE 结果偏小。PE(0,0) 少 1（期望 30 得 29），PE(3,3) 少 110（期望 126 得 16）。

### 根因

**FEED_CYCLES 计算错误**。

原公式：`FEED_CYCLES = K + max(M, N) - 1`

数据流时序：
1. 边界组合逻辑在周期 `c` 输出数据
2. PE 在下一个 posedge（周期 `c+1`）累加
3. 最后一次累加：PE(M-1,N-1) 在周期 `(K-1)+(M-1)+(N-1)+1 = K+M+N-2`
4. `en` 必须在周期 `K+M+N-3` 仍然为高
5. 因此 `FEED_CYCLES = K+M+N-2`

原公式 `K+max(M,N)-1` 比正确值小 `min(M,N)-1` 个周期。数据在最后一个 FEED 周期进入边界，但要到 DRAIN 阶段才到达 PE，此时 `en` 已变低。

影响范围：所有 `i+j >= max(M,N)` 的 PE 都丢失最后 `min(M,N)-1` 个乘积。

### 修改内容

**src/systolic_array.v**
- `FEED_CYCLES` 从 `K+max(M,N)-1` 改为 `K+M+N-2`
- `DRAIN_CYCLES` 从 `max(M,N)` 改为 `1`（所有数据在 FEED 阶段已累积完毕）
- `feed_cnt` 位宽相应调整

**tb/tb_systolic_array.v**
- `fc` 计算从 `max(K,M,N)+K-1` 改为 `K+M+N-2`

**tb/tb_overflow.v**
- `feed_cycles` 同步修改

**scripts/debug_sim.py** — Python 仿真器，复现并验证修复
**scripts/verify_bug.py** — FEED_CYCLES 计算验证
**scripts/verify_fix.py** — 多尺寸矩阵验证（11 组全部 PASS）

### 验证

Python 仿真验证：
- 4×4×4：全部 16 个 PE 结果正确（修复前 6 个错误）
- 11 种矩阵尺寸全部 PASS（含 1×1×1、矩形 3×5×7、8×8×8 等）

### 设计决策

为什么 DRAIN_CYCLES 改为 1：
- 原设计 DRAIN 用于"流水线排空"，但 staggered feeding 下数据在 FEED 阶段已经全部到达 PE
- DRAIN 阶段 `en=0`，PE 不累加，只用于 `c_valid` 信号
- 1 个周期足够让 `c_valid` 在 `drain_done` 时断言

---

## [2026-04-29] MiMo — 工作流程优化

### 修改内容
- **ai/AGENTS.md** — 大幅扩充
  - 新增模块依赖关系图
  - 新增 Debug 流程（6 步：缩小规模 → 加调试打印 → 看波形 → 手推时序 → 对比期望 → 记录发现）
  - 新增常见 Verilog 陷阱（事件调度竞争、$clog2(1) 边界、有符号数扩展、generate 信号连接）
  - 新增快速验证清单（改代码前/后各跑什么）
  - 新增"标记完成的规则"：只有仿真通过才能标 ✅
  - 补充 tb_overflow.v 到仓库结构
  - 补充 PLAN.md 到仓库结构

- **ai/TODO.md** — 结构重组
  - 重新编号，按 Phase 组织任务
  - Phase 1 已实现功能标记为 🟡 进行中（代码完成但未仿真验证）
  - 添加顶部规则："只有仿真通过后才能标记 ✅"
  - Phase 3+ 按需推进，不再占用高优先级位置

- **ai/PLAN.md** — 状态修正
  - Phase 0.1 改为 🟡 进行中（当前阻塞项）
  - Phase 1.1-1.4 全部改为 🟡 进行中（代码完成，待仿真验证）
  - 原因：未跑过仿真的代码不应标记为 ✅ 完成

### 设计决策
- 为什么重写 AGENTS.md 而不是小补丁：原版缺少 debug 流程和陷阱记录，这两样对后续 AI 至关重要，分散添加不如一次性整理好
- 为什么 Phase 1 改为"进行中"：PLAN.md 自己写了"先验证再优化"，但 Phase 1 标了 ✅ 而 Phase 0 全 ⬜，逻辑矛盾

### 已知问题
- 当前环境无 iverilog，无法实际验证仿真状态

---

## [2026-04-29] MiMo (xiaomi/mimo-v2.5-pro) — Debug: 数据对齐问题定位与架构修复（进行中）

### 问题发现

安装 iverilog 并运行 `make sim` 后，**所有测试失败**。结果系统性偏小，对角线及右下区域逐步归零。

**根因分析**：脉动阵列存在**数据对齐 (data alignment) 问题**。

原设计中，A 和 B 的边界输入同时喂入（每周期所有行/列同时送数据）。但在脉动阵列内部：
- A 向右传播：A[i][k] 到达 PE(i,j) 需要 j 个周期（经过 j 个 PE 的流水线寄存器）
- B 向下传播：B[k][j] 到达 PE(i,j) 需要 i 个周期（经过 i 个 PE 的流水线寄存器）
- **到达时间差 = j − i ≠ 0**（对于非对角线 PE）

这导致 A[i][k] 和 B[k][j] 无法在同一周期到达 PE(i,j)，累加的是错误的数据对。

**验证方法**：
- Test 1 (4×4)：C[0][0] 期望 30，实际 29（少了 A[0][0]×B[0][0]=1 的贡献）
- Test 3 (identity)：C[0][0]=0（完全丢失），C[3][3]=0（完全丢失）
- 溢出测试：期望 127 饱和，实际 64（只累加了一个 64，丢失第二个）

### 修复方案

**错开喂入 (Staggered Feeding)**：

改变边界输入逻辑，使 A 和 B 在不同时刻进入阵列：
- **A[i][k]** 在 FEED 周期 **k+i** 进入 PE(i,0)（按行错开）
- **B[k][j]** 在 FEED 周期 **k+j** 进入 PE(0,j)（按列错开）
- 两者到达 PE(i,j) 的时刻 = k+i+j，**天然对齐** ✓

边界改为**纯组合逻辑**（去掉寄存器），由 testbench 控制精确时序。

### 修改内容

**src/systolic_array.v — 边界逻辑重写**
- A 边界：`pe_a_in[i][0]` 从 registered 改为 combinational
  - 仅在 `feed_cnt >= i && feed_cnt - i < K_DIM` 时输出 a_data[i]
- B 边界：同样改为 combinational，条件 `feed_cnt >= j && feed_cnt - j < K_DIM`
- FEED_CYCLES 改为 `K_DIM + max(M_ROWS, N_COLS) - 1`（容纳错开数据）
- DRAIN_CYCLES 改为 `max(M_ROWS, N_COLS)`（流水线排空）

**tb/tb_systolic_array.v — 完全重写**
- `feed_matrices` task 重写为错开喂入模式
- 数据在 `@(posedge clk)` **之前**设置（确保组合逻辑边界在边沿读到正确值）
- 所有 6 个测试使用统一的 feed_matrices task
- back-to-back 测试 (Test 6) 也使用 feed_matrices

**tb/tb_overflow.v — 重写**
- 使用相同的错开喂入模式
- 增加 FEED_CYCLES 计算逻辑

### 验证

仿真结果（当前状态，**仍有 1 周期偏移 bug**）：

```
=== Test 1: Known values (4×4 × 4×4) ===
  Expected:         Got:
    30  40  50  60    29  38  47  56
    40  54  68  82    38  50  62  74
    50  68  86 104    47  62  77  50
    60  82 104 126    56  74  50  25
```

**改进**：从原来的 C[3][3]=0（完全不对齐）到现在 C[3][3]=25（接近但仍有偏移）。
误差模式：每个 PE 丢失约 1 个乘积的累加，说明错开喂入方向正确但时序仍有 1 拍偏差。

### 待解决

1. **时序偏移 1 周期**：PE(0,0) 结果 29 vs 期望 30，每个 PE 都少累加约 1 个乘积
2. **需加 debug 波形**：在 testbench 中监视 `dut.pe_a_in[0][0]` / `dut.pe_b_in[0][0]` / `dut.u_pe[0].accum` 来定位丢失时刻
3. **可能原因**：testbench 数据设置与组合逻辑边界读取之间的 Verilog 事件调度竞争——数据在 `@(posedge clk)` 同一时间槽内更新，边界可能读到旧值

### 设计决策

1. **为什么选择组合逻辑边界（而非在 PE 内加延迟）**
   - 不修改 PE 核心逻辑，保持可综合性
   - 边界逻辑简单，只在 generate 块中用 assign
   - testbench 完全控制时序，灵活度最高

2. **为什么 A 和 B 都错开（而非只错开一个）**
   - A 路径延迟 = j（PE 链），B 路径延迟 = i（PE 链）
   - 差值 = j-i，随 PE 位置变化
   - 只错开一个无法消除所有 PE 的对齐误差
   - 两者都错开 k+i 和 k+j，到达时间恒为 k+i+j

3. **替代方案（未采用）**
   - PE 内部加 b_in 延迟寄存器：增加面积，改变 PE 接口
   - A 边界加 i 周期延迟：需要 M_ROWS 个不同深度的 FIFO
   - 同时喂入 + 调整 PE 内部时序：太复杂，容易出错

### 已知问题

1. **仿真仍有 bug**：PE(0,0) 结果差 1，需继续 debug（用波形定位）
2. **`$clog2(1)` 边界**：M_ROWS=1 或 N_COLS=1 时端口宽度计算可能出错
3. **未测试矩形矩阵**：当前只测了 4×4×4 方阵

---

## [2026-04-29] MiMo (xiaomi/mimo-v2.5-pro) — 代码审查与 Bug 修复

### 修改内容

**src/pe.v — 修复 PE 数据传递门控问题**
- 将 `a_out`/`b_out` 的更新逻辑从 `en` 门控改为始终更新
- 原来：只在 `en=1`（S_FEED）时更新，DRAIN 阶段输出冻结
- 现在：每个时钟沿都更新，零值在 DRAIN 阶段正常传播
- 效果：pipeline 在非计算阶段保持流动，消除残留数据

**tb/tb_overflow.v — 修复三个问题**
1. 补全缺失的端口连接（row_sel, col_sel, c_read_data, cycle_count, overflow_count）
2. 添加负溢出测试的完整分析文档（解释为何 K=2, 4-bit 参数下无法触发负溢出）
3. 删除死代码（空循环 `for (...) ;`）
4. 初始化 row_sel/col_sel

### 设计决策

**PE 数据传递解耦**：
- 选择方案：去掉 `if (en)` 门控，改为 `else` 无条件更新
- 替代方案：增加独立的 `pass_through_en` 信号（更灵活但增加端口）
- 理由：数据传递本质上是纯寄存器流水线，不需要与累加使能耦合
- 影响：a_out/b_out 在 IDLE/DONE 时也更新，但边界输入已为零，不影响功能

### 验证
- 未实际仿真（环境无 iverilog）
- 通过代码推演确认修复正确性

---

## [2026-04-29] MiMo (xiaomi/mimo-v2.5-pro) — Phase 1.1: 溢出检测与饱和运算

### 修改内容
- **src/pe.v** — 增加溢出检测和饱和逻辑
- **src/systolic_array.v** — 暴露溢出信号
- **src/systolic_array_top.v** — 传递 `any_overflow`
- **tb/tb_overflow.v** — 专用溢出测试台
- **tb/tb_systolic_array.v** — 增加溢出检测测试用例
- **Makefile** — 增加 `make overflow` 目标

### 设计决策
- overflow 标志是 sticky 的（一旦触发保持到清零），避免瞬时溢出被遗漏
- 饱和逻辑在累加器更新时判断，而非结果输出时

---

## [2026-04-29] MiMo (xiaomi/mimo-v2.5-pro) — 初始实现

### 修改内容
从零开始实现完整的脉动阵列矩阵乘法器：

- **src/pe.v** — 处理单元（有符号 MAC，清零/使能控制，数据传递寄存器）
- **src/systolic_array.v** — 顶层阵列（M×N PE，4 状态 FSM，边界输入逻辑）
- **src/systolic_array_top.v** — 可配置包装
- **tb/tb_systolic_array.v** — 测试平台（已知值/随机/单位阵测试）
- **Makefile** — 构建系统
- **scripts/run_sim.sh** — 仿真脚本
- **README.md** — 项目文档
- **ai/** — AI 协作基础设施

### 设计决策
1. **clear_acc 时机**：在 IDLE/DONE 状态清零，避免 FEED 首周期竞争
2. **矩形矩阵支持**：M×K × K×N，PE 阵列大小 M_ROWS × N_COLS
3. **参数化**：所有模块通过 parameter 支持可配置大小
