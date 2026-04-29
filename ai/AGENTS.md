# AGENTS.md — AI 工作指南

这是由 AI 创建和维护的硬件设计项目。请在开始工作前仔细阅读本文件。

## 项目概述

**脉动阵列矩阵乘法器 (Systolic Array Matrix Multiplier)**

可配置大小的 RTL 设计，支持任意 M×K × K×N 有符号整数矩阵乘法。
使用 Verilog 编写，Icarus Verilog 仿真验证。

## 仓库结构

```
├── src/
│   ├── pe.v                  # 处理单元 (Processing Element)
│   ├── systolic_array.v      # 顶层脉动阵列 + FSM 控制器
│   └── systolic_array_top.v  # 可配置包装模块
├── tb/
│   ├── tb_systolic_array.v   # 测试平台
│   └── tb_overflow.v         # 溢出专用测试
├── scripts/
│   └── run_sim.sh            # 仿真脚本
├── ai/
│   ├── AGENTS.md             # ← 你正在读的文件
│   ├── DESIGN.md             # 架构设计文档
│   ├── WORKLOG.md            # AI 工作日志（记录每次修改）
│   ├── TODO.md               # 待办事项
│   └── PLAN.md               # 演进路线图
├── Makefile
└── README.md
```

## 模块依赖关系

```
pe.v  ──────────────────────┐
                            ├──→ systolic_array.v ──→ systolic_array_top.v
tb_systolic_array.v ────────┘         │
tb_overflow.v ────────────────────────┘
```

- `pe.v` 是最小单元，无外部依赖
- `systolic_array.v` 实例化 M×N 个 PE
- `systolic_array_top.v` 是可配置包装（当前内容较少）
- 所有 testbench 依赖 `systolic_array.v`

## 工作流程

### 开始前（必须按顺序）

1. **读 `ai/DESIGN.md`** — 理解架构和设计决策
2. **读 `ai/WORKLOG.md`** — 了解之前 AI 做了什么，特别是最近的修改和已知问题
3. **读 `ai/TODO.md`** — 当前待办事项和优先级
4. **运行仿真**验证现有功能：`make sim`
5. **如果仿真失败** → 进入下方 [Debug 流程](#debug-流程)

### 修改代码时

1. **先运行仿真**确认当前代码是正确的：`make sim`
2. **做修改**（每次改一个东西，不要批量改）
3. **再运行仿真**确认修改没有破坏已有功能
4. **添加新测试**（如果引入了新功能）
5. **更新 `ai/WORKLOG.md`** 记录你的修改
6. **更新 `ai/TODO.md`** 标记完成的项目、添加新发现的问题
7. **Commit** 使用清晰的 commit message

### ⚠️ 标记完成的规则

**只有仿真通过后才能标记任务为 ✅ 完成。** 代码写完但未验证 → 标记为 🟡 进行中。

### Commit Message 规范

```
feat: 新功能描述
fix: 修复描述
refactor: 重构描述
test: 测试相关
docs: 文档更新
perf: 性能优化
```

## Debug 流程

当测试失败时，**不要急着改代码**。按以下步骤定位问题：

### Step 1: 缩小规模

用最小参数复现问题：
```bash
make sim M=2 K=2 N=2    # 最小有意义的矩阵
```
小矩阵更容易手推时序。

### Step 2: 加调试打印

在 testbench 中添加 `$display` 监视关键信号：
```verilog
// 在 always @(posedge clk) 中添加
$display("t=%0t state=%0d feed_cnt=%0d pe_a_in[0][0]=%0d pe_b_in[0][0]=%0d accum=%0d",
         $time, dut.state, dut.feed_cnt,
         dut.pe_a_in[0][0], dut.pe_b_in[0][0], dut.u_pe[0][0].accum);
```

### Step 3: 看波形

```bash
make wave   # 打开 GTKWave
```
逐周期检查：
- 边界输入是否在正确时刻出现
- PE 的 a_in/b_in 是否对齐
- 累加器值是否符合预期

### Step 4: 手推时序

在纸上画出每个 PE 在每个周期收到的 a/b 值：

```
        Cycle 0   Cycle 1   Cycle 2   Cycle 3
PE(0,0) A[0][0]   A[0][1]   A[0][2]   A[0][3]
        B[0][0]   B[0][1]   B[0][2]   B[0][3]
PE(0,1) 0→        A[0][0]→  A[0][1]→  A[0][2]→
        B[1][0]   B[1][1]   B[1][2]   B[1][3]
...
```

### Step 5: 对比期望

用 Python/Excel 计算每步累加值，与仿真输出逐拍对比。

### Step 6: 记录发现

**先写 WORKLOG，再改代码。** 记录：
- 现象是什么
- 根因是什么
- 尝试了什么方案
- 为什么选择这个方案

## 常见陷阱（Verilog 特有）

### 事件调度竞争

```verilog
// ❌ 错误：组合逻辑边界可能读到旧值
@(posedge clk);
a_data[i] = new_value;  // 在同一时间槽更新

// ✅ 正确：先设数据，再等边沿
a_data[i] = new_value;
@(posedge clk);         // 组合逻辑在此边沿读到新值
```

**原因**：Verilog 的 NBA (Non-Blocking Assignment) 在同一个 `@(posedge clk)` 时间槽内，组合逻辑先于顺序块执行。如果数据在 `@(posedge clk)` 之后才更新，组合逻辑读到的是上一拍的值。

### `$clog2(1)` 边界

```verilog
// $clog2(1) = 0，导致位宽为 0 的 wire
// 解决：用 ($clog2(N) > 0 ? $clog2(N) : 1) 或确保 N >= 2
```

### 有符号数扩展

```verilog
// ❌ 错误：无符号乘法
result = a_in * b_in;

// ✅ 正确：显式 $signed
result = $signed(a_in) * $signed(b_in);
```

### `generate` 中的信号连接

```verilog
// generate 块中的 if/else 只在编译时求值
// 运行时条件要用三元运算符或 assign
```

## 关键设计约束

1. **有符号运算**：所有数据都是有符号整数 (`signed`)
2. **参数化**：所有模块必须通过 `parameter` 支持可配置大小
3. **时序正确**：数据流必须对齐，A[i][k] 和 B[k][j] 必须在同一周期到达 PE(i,j)
4. **可综合**：RTL 代码必须可综合（不要用 `initial`、`#delay` 等不可综合结构）
5. **仿真验证**：每次修改必须通过 `make sim` 的全部测试

## 快速验证清单

改代码**前**：
- [ ] `make sim` — 确认当前代码是绿的
- [ ] 读 WORKLOG — 了解最近改了什么

改代码**后**：
- [ ] `make sim` — 默认 4×4×4 通过
- [ ] `make sim M=2 K=2 N=2` — 最小矩阵通过
- [ ] `make sim M=3 K=5 N=7` — 矩形矩阵通过（如果改了数据流）
- [ ] 更新 WORKLOG
- [ ] 更新 TODO

## 仿真

```bash
# 安装仿真器（如果没有）
sudo apt install iverilog

# 运行仿真
make sim                    # 默认 4×4×4
make sim M=8 K=8 N=8       # 8×8 矩阵
make sim M=3 K=5 N=7       # 矩形矩阵
make sim W=16              # 16-bit 位宽

# 溢出测试
make overflow

# 波形调试
make wave
```

## 已知问题

见 `ai/TODO.md` 和 `ai/WORKLOG.md` 中的"已知问题"章节。

## 扩展方向

- 浮点支持 (IEEE 754)
- 分块计算（大矩阵拆分成小块）
- AXI-Stream 接口
- FPGA 综合脚本 (Vivado/Quartus)
- 性能基准测试
- 功耗优化
