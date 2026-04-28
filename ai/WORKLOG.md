# WORKLOG.md — AI 工作日志

每次 AI 修改代码时，必须在此文件顶部添加一条记录。

格式：
```
## [日期] AI名称 — 简要描述

### 修改内容
- 具体修改了哪些文件
- 做了什么改动

### 设计决策
- 为什么这样做
- 考虑过的替代方案

### 验证
- 运行了哪些测试
- 结果如何

### 已知问题
- 发现但未修复的问题
```

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

**负溢出测试分析**：
- DATA_WIDTH=4, K_DIM=2, ACCUM_WIDTH=8 时：
  - 最小可能累加值 = (-8)×7 × 2 = -112
  - 8-bit 最小值 = -128
  - -112 > -128，无法溢出
- 结论：负溢出需要更大的 K_DIM 或更小的 ACCUM_WIDTH 才能触发

### 验证
- 未实际仿真（环境无 iverilog）
- 通过代码推演确认修复正确性
- **需要用户运行 `make sim` 和 `make overflow` 验证**

### 发现但未修复的问题

1. **$clog2(1) 边界**：当 M_ROWS=1 或 N_COLS=1 时，`$clog2(1)-1` = -1，端口宽度为 `[-1:0]`，部分工具可能报错。实际使用中不太可能出现 1×1 阵列。

2. **overflow_count 位宽**：8-bit 最多计数 255 个 PE 溢出。当阵列 > 16×16（256 PE）时会溢出。默认 4×4 无问题。

3. **随机测试范围**：`$urandom_range(0, 2**DATA_WIDTH - 2)` 生成 -128 到 126，不包含 127。这是有意为之（避免 127 作为被减数时的边界问题），但覆盖率不完整。

---

## [2026-04-29] MiMo (xiaomi/mimo-v2.5-pro) — Phase 1.1: 溢出检测与饱和运算

### 修改内容
- **src/pe.v** — 增加溢出检测和饱和逻辑
  - 检测 `accum + product` 的正溢出和负溢出
  - 溢出时 clamp 到 `SAT_MAX`/`SAT_MIN` 而非 wrap
  - 增加 `overflow` 标志（sticky，清零时复位）
  - 使用独立的 `product` wire 提高可读性

- **src/systolic_array.v** — 暴露溢出信号
  - 收集所有 PE 的 `overflow` 标志
  - 输出 `any_overflow`（OR 归约）

- **src/systolic_array_top.v** — 传递 `any_overflow`

- **tb/tb_overflow.v** — 专用溢出测试台
  - 4-bit 数据、8-bit 累加器
  - (-8)×(-8) + (-8)×(-8) = 128 → 饱和到 127

- **tb/tb_systolic_array.v** — 增加溢出检测测试用例

- **Makefile** — 增加 `make overflow` 目标

### 设计决策
- overflow 标志是 sticky 的（一旦触发保持到清零），避免瞬时溢出被遗漏
- 饱和逻辑在累加器更新时判断，而非结果输出时
- 正溢出和负溢出分开检测（同号相加异号结果）

### 已知问题
- 未实际仿真验证（无 iverilog）

## [2026-04-29] MiMo (xiaomi/mimo-v2.5-pro) — 初始实现

### 修改内容
从零开始实现完整的脉动阵列矩阵乘法器：

- **src/pe.v** — 处理单元
  - 有符号乘累加器 (MAC)
  - 清零、使能控制
  - 数据传递寄存器 (a_out, b_out)

- **src/systolic_array.v** — 顶层阵列
  - M×N PE 阵列，generate 实例化
  - 4 状态 FSM (IDLE → FEED → DRAIN → DONE)
  - 边界输入逻辑
  - 流水线延迟计算

- **src/systolic_array_top.v** — 可配置包装
  - 支持 Verilog `define 覆盖参数

- **tb/tb_systolic_array.v** — 测试平台
  - 三组测试：已知值、随机、单位阵
  - 软件参考模型对比

- **Makefile** — 构建系统
- **scripts/run_sim.sh** — 仿真脚本
- **README.md** — 项目文档
- **ai/** — AI 协作基础设施

### 设计决策

1. **clear_acc 时机选择**
   - 最初在 FEED 状态的第一个周期清零（与 en 同时有效）
   - 问题：clear_acc 和 en 同时有效时，PE 中 clear 优先于累加，导致丢失第一个 A[0][0]*B[0][0]
   - 最终方案：在 IDLE/DONE 状态清零，进入 FEED 时累加器已经为零

2. **数据喂入时序**
   - 测试平台最初在 FSM 转换到 S_FEED 的同一时钟沿设置数据
   - 问题：非阻塞赋值导致 FSM 看到的是上一周期的数据，产生 1 周期偏移
   - 最终方案：在 assert valid 之前预设 k=0 的数据，后续数据在每个时钟沿前更新

3. **矩形矩阵支持**
   - 选择 M×K × K×N 而非仅 N×N 方阵
   - PE 阵列大小为 M_ROWS × N_COLS，与 K_DIM 无关

### 验证

仿真环境未安装 Icarus Verilog，代码通过以下方式验证：
- 手动推演 4×4 × 4×4 时序（12 个时钟周期）
- 逐周期检查 PE 累加时序
- 检查 clear_acc/en 竞争条件
- 测试平台时序对齐检查

**⚠️ 需要实际运行仿真验证！** 运行 `make sim` 确认。

### 已知问题

1. **未实际仿真验证** — 环境无 iverilog，需要用户本地运行确认
2. **累加器溢出** — ACCUM_WIDTH 默认 32-bit，对大矩阵或大数值可能不够
3. **综合未验证** — 代码写法可综合，但未用 Vivado/Quartus 验证
