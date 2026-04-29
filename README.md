# Systolic Array Matrix Multiplier

可配置大小的脉动阵列（Systolic Array）矩阵乘法器，支持任意 M×K × K×N 矩阵乘法。

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

- **A 矩阵**：从左边界进入，逐行向右传播
- **B 矩阵**：从上边界进入，逐列向下传播
- **每个 PE**：执行 `accum += a_in × b_in`，同时将数据传递给右/下邻居
- A 和 B 数据在每个 PE 的时钟周期对齐，确保 `C[i][j] = Σ_k A[i][k] × B[k][j]`

### 流水线延迟

从开始喂入数据到结果有效，总共需要 **M + N + K** 个时钟周期。

## 文件结构

```
├── src/
│   ├── pe.v                 # 处理单元 (Processing Element)
│   └── systolic_array.v     # 顶层脉动阵列模块
├── tb/
│   └── tb_systolic_array.v  # 测试平台
├── scripts/
│   └── run_sim.sh           # 仿真脚本
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

    // 矩阵 A 输入（每周期每行一个元素）
    input  wire signed [DATA_WIDTH-1:0] a_data [0:M_ROWS-1],
    input  wire                     a_valid,
    output wire                     a_ready,

    // 矩阵 B 输入（每周期每列一个元素）
    input  wire signed [DATA_WIDTH-1:0] b_data [0:N_COLS-1],
    input  wire                     b_valid,
    output wire                     b_ready,

    // 结果输出
    output wire signed [ACCUM_WIDTH-1:0] c_data [0:M_ROWS-1][0:N_COLS-1],
    output reg                      c_valid,
    output wire                     busy
);
```

### 使用流程

1. **等待空闲**：`busy == 0`
2. **开始喂数据**：同时拉高 `a_valid` 和 `b_valid`，每周期送入一列 A 和一行 B
   - `a_data[i]` = `A[i][k]`（第 k 轮，所有行同时送）
   - `b_data[j]` = `B[k][j]`（第 k 轮，所有列同时送）
3. **喂完 K 个周期后**：拉低 `a_valid`/`b_valid`
4. **等待结果**：`c_valid` 拉高时，`c_data` 包含最终结果

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
Cycle 10: feed_cnt=9，最后一次累加（PE(3,3) 收到 A[3][3]×B[3][3]）
Cycle 11: DRAIN，c_valid 有效，结果就绪
```

总延迟 = K + M + N - 1 = 4 + 4 + 4 - 1 = 11 周期

FEED_CYCLES = K + M + N - 2 = 10（边界组合逻辑输出延迟 + PE 流水线寄存器需要额外 1 周期累加）

## License

MIT
