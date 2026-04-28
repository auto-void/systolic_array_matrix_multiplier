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
│   └── tb_systolic_array.v   # 测试平台
├── scripts/
│   └── run_sim.sh            # 仿真脚本
├── ai/
│   ├── AGENTS.md             # ← 你正在读的文件
│   ├── DESIGN.md             # 架构设计文档
│   ├── WORKLOG.md            # AI 工作日志（记录每次修改）
│   └── TODO.md               # 待办事项
├── Makefile
└── README.md
```

## 工作流程

### 开始前

1. **读 `ai/DESIGN.md`** — 理解架构和设计决策
2. **读 `ai/WORKLOG.md`** — 了解之前 AI 做了什么
3. **读 `ai/TODO.md`** — 当前待办事项
4. **运行仿真**验证现有功能：`make sim`

### 修改代码时

1. **先运行仿真**确认当前代码是正确的：`make sim`
2. **做修改**
3. **再运行仿真**确认修改没有破坏已有功能
4. **添加新测试**（如果引入了新功能）
5. **更新 `ai/WORKLOG.md`** 记录你的修改
6. **更新 `ai/TODO.md`** 标记完成的项目、添加新发现的问题
7. **Commit** 使用清晰的 commit message

### Commit Message 规范

```
feat: 新功能描述
fix: 修复描述
refactor: 重构描述
test: 测试相关
docs: 文档更新
perf: 性能优化
```

## 关键设计约束

1. **有符号运算**：所有数据都是有符号整数 (`signed`)
2. **参数化**：所有模块必须通过 `parameter` 支持可配置大小
3. **时序正确**：数据流必须对齐，A[i][k] 和 B[k][j] 必须在同一周期到达 PE(i,j)
4. **可综合**：RTL 代码必须可综合（不要用 `initial`、`#delay` 等不可综合结构）
5. **仿真验证**：每次修改必须通过 `make sim` 的全部测试

## 仿真

```bash
# 安装仿真器（如果没有）
sudo apt install iverilog

# 运行仿真
make sim                    # 默认 4×4×4
make sim M=8 K=8 N=8       # 8×8 矩阵
make sim M=3 K=5 N=7       # 矩形矩阵
make sim W=16              # 16-bit 位宽
```

## 已知问题

见 `ai/TODO.md`。

## 扩展方向

- 浮点支持 (IEEE 754)
- 分块计算（大矩阵拆分成小块）
- AXI-Stream 接口
- FPGA 综合脚本 (Vivado/Quartus)
- 性能基准测试
- 功耗优化
