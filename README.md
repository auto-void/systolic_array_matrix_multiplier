# Systolic Array Matrix Multiplier

可配置大小的脉动阵列（Systolic Array）矩阵乘法器，支持任意 M×K × K×N 有符号整数矩阵乘法。

## 架构

```
      B[0][*]   B[1][*]   B[2][*]   B[3][*]
          v         v         v         v
      +-------+ +-------+ +-------+ +-------+
A[0]->|PE(0,0)|>|PE(0,1)|>|PE(0,2)|>|PE(0,3)|-> C[0]
      +---+---+ +---+---+ +---+---+ +---+---+
          v         v         v         v
      +-------+ +-------+ +-------+ +-------+
A[1]->|PE(1,0)|>|PE(1,1)|>|PE(1,2)|>|PE(1,3)|-> C[1]
      +---+---+ +---+---+ +---+---+ +---+---+
          v         v         v         v
      +-------+ +-------+ +-------+ +-------+
A[2]->|PE(2,0)|>|PE(2,1)|>|PE(2,2)|>|PE(2,3)|-> C[2]
      +---+---+ +---+---+ +---+---+ +---+---+
          v         v         v         v
      +-------+ +-------+ +-------+ +-------+
A[3]->|PE(3,0)|>|PE(3,1)|>|PE(3,2)|>|PE(3,3)|-> C[3]
      +-------+ +-------+ +-------+ +-------+
```

### 数据流

采用**错开喂入 (Staggered Feeding)** 保证数据对齐：

- **A 矩阵**：`A[i][k]` 在 FEED 周期 `k+i` 从左边界进入 PE(i,0)，逐周期向右传播
- **B 矩阵**：`B[k][j]` 在 FEED 周期 `k+j` 从上边界进入 PE(0,j)，逐周期向下传播
- **对齐保证**：两者到达 PE(i,j) 的时刻均为 `k+i+j`，天然对齐
- **边界逻辑**：纯组合逻辑，由内部 `feed_cnt` 控制选通
- **每个 PE**：执行 `accum += a_in × b_in`（有符号乘累加），同时将数据寄存传递给右/下邻居

### 流水线延迟

```
FEED_CYCLES = K + M + N - 2   （数据喂入 + 累加）
DRAIN_CYCLES = 1               （c_valid 断言）
总延迟 = K + M + N - 1 个时钟周期
```

示例（4×4 × 4×4）：总延迟 = 4 + 4 + 4 - 1 = 11 周期

## 文件结构

```
├── src/
│   ├── pe.v                  # 处理单元 (Processing Element)
│   ├── systolic_array.v      # 顶层脉动阵列 + FSM 控制器
│   └── systolic_array_top.v  # 可配置包装模块
├── tb/
│   ├── tb_systolic_array.v   # 测试平台
│   └── tb_overflow.v         # 溢出专用测试
├── scripts/
│   ├── run_sim.sh            # 仿真脚本
│   ├── debug_sim.py          # Python 仿真调试器
│   ├── verify_bug.py         # FEED_CYCLES 验证
│   └── verify_fix.py         # 多尺寸验证
├── ai/
│   ├── AGENTS.md             # AI 工作指南
│   ├── DESIGN.md             # 架构设计文档
│   ├── WORKLOG.md            # AI 工作日志
│   ├── TODO.md               # 待办事项
│   ├── PLAN.md               # 演进路线图
│   └── BUGS.md               # Bug 追踪
├── Makefile
└── README.md
```

## 可配置参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `M_ROWS` | A 矩阵行数 / C 矩阵行数 | 4 |
| `K_DIM` | A 矩阵列数 / B 矩阵行数 | 4 |
| `N_COLS` | B 矩阵列数 / C 矩阵列数 | 4 |
| `DATA_WIDTH` | 数据位宽（有符号整数） | 8 |
| `ACCUM_WIDTH` | 累加器位宽 | 32 |

建议：`ACCUM_WIDTH >= DATA_WIDTH * 2 + $clog2(K_DIM)`

## 接口

```verilog
module systolic_array #(
    parameter M_ROWS     = 4,
    parameter K_DIM      = 4,
    parameter N_COLS     = 4,
    parameter DATA_WIDTH = 8,
    parameter ACCUM_WIDTH = 32
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // 矩阵 A 输入（行串行）
    input  wire signed [DATA_WIDTH-1:0] a_data [0:M_ROWS-1],
    input  wire                     a_valid,
    output wire                     a_ready,

    // 矩阵 B 输入（列串行）
    input  wire signed [DATA_WIDTH-1:0] b_data [0:N_COLS-1],
    input  wire                     b_valid,
    output wire                     b_ready,

    // 结果输出（全矩阵直连 PE 累加器）
    output wire signed [ACCUM_WIDTH-1:0] c_data [0:M_ROWS-1][0:N_COLS-1],
    output reg                      c_valid,
    output wire                     busy,
    output wire                     any_overflow,

    // 结果读出（地址选择单元素访问）
    input  wire [$clog2(M_ROWS)-1:0] row_sel,
    input  wire [$clog2(N_COLS)-1:0] col_sel,
    output wire signed [ACCUM_WIDTH-1:0] c_read_data,

    // 状态输出
    output wire [31:0]              cycle_count,
    output wire [7:0]               overflow_count
);
```

### 使用流程

1. **等待空闲**：`busy == 0`
2. **开始喂数据**：同时拉高 `a_valid` 和 `b_valid`，保持整个 FEED_CYCLES 期间为高
   - 边界组合逻辑根据内部 `feed_cnt` 自动选通正确的 A[i][k]/B[k][j]
   - 用户每周期设置 `a_data[i]` 和 `b_data[j]`
3. **等待完成**：`c_valid` 拉高时，`c_data` 包含最终结果
4. **读出结果**：通过 `row_sel`/`col_sel` 地址选择读出单个元素，或直接使用 `c_data` 全矩阵输出

## 快速仿真

```bash
# 安装 Icarus Verilog（如果没装）
sudo apt install iverilog

# 默认 4×4 × 4×4
make sim

# 自定义大小
make sim M=8 K=8 N=8

# 矩形矩阵
make sim M=3 K=5 N=7

# 16 位数据宽度
make sim M=4 K=4 N=4 W=16

# 溢出/饱和测试（4-bit data, 8-bit accum）
make overflow

# 查看波形（需要 GTKWave）
make wave
```

或使用脚本：

```bash
./scripts/run_sim.sh --rows 4 --cols 4 --k 4 --width 8
```

## 时序示例

对于 4×4 × 4×4 矩阵乘法（M=4, K=4, N=4）：

```
Cycle 0:  IDLE，累加器清零
Cycle 1:  FEED 开始，feed_cnt=0，边界输出 A[i][0]/B[0][j]
Cycle 2:  feed_cnt=1，错开喂入（A[i][1]/B[1][j] + 流水传播）
Cycle 3:  feed_cnt=2
  ...
Cycle 9:  feed_cnt=8
Cycle 10: feed_cnt=9，边界输出最后有效数据
Cycle 11: DRAIN，c_valid 有效，结果就绪
```

FEED_CYCLES = K + M + N - 2 = 10（feed_cnt 0~9），总延迟 = K + M + N - 1 = 11 周期。

> 详细时序分析见 `ai/DESIGN.md` 第 2-3 节。

## 已知问题

见 `ai/BUGS.md`。当前主要问题：

- 🔴 Testbench 数据设置时序有 1 周期偏移（仿真结果不正确）
- 🔴 `en` 信号比状态转移晚 1 周期
- 🟡 `$clog2(1)` 在 M=1 或 N=1 时导致零宽度端口

## License

MIT
