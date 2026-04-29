# DEBUG_GUIDE.md — Debug 流程与常见陷阱

当测试失败时，**不要急着改代码**。按以下步骤定位问题。

## Step 1: 缩小规模

用最小参数复现问题：
```bash
make sim M=2 K=2 N=2    # 最小有意义的矩阵
```
小矩阵更容易手推时序。

## Step 2: 加调试打印

在 testbench 中添加 `$display` 监视关键信号：
```verilog
// 在 always @(posedge clk) 中添加
$display("t=%0t state=%0d feed_cnt=%0d pe_a_in[0][0]=%0d pe_b_in[0][0]=%0d accum=%0d",
         $time, dut.state, dut.feed_cnt,
         dut.pe_a_in[0][0], dut.pe_b_in[0][0], dut.u_pe[0][0].accum);
```

## Step 3: 看波形

```bash
make wave   # 打开 GTKWave
```
逐周期检查：
- 边界输入是否在正确时刻出现
- PE 的 a_in/b_in 是否对齐
- 累加器值是否符合预期

## Step 4: 手推时序

在纸上画出每个 PE 在每个周期**收到**的 a/b 值（注意：累加发生在收到的下一个周期）：

```
         feed_cnt=0  feed_cnt=1  feed_cnt=2  feed_cnt=3
PE(0,0)  A[0][0]     A[0][1]     A[0][2]     A[0][3]
         B[0][0]     B[0][1]     B[0][2]     B[0][3]
PE(0,1)  0           A[0][0]→    A[0][1]→    A[0][2]→
         B[1][0]     B[1][1]     B[1][2]     B[1][3]
PE(1,0)  0           A[1][0]     A[1][1]     A[1][2]
         0           B[0][0]↓    B[0][1]↓    B[0][2]↓
...

边界组合逻辑在 feed_cnt=c 时输出数据，PE 在下一个 posedge（c+1）累加。
→ 表示 A 从左邻居传递（延迟 1 周期），↓ 表示 B 从上邻居传递。
```

## Step 5: 对比期望

用 Python/Excel 计算每步累加值，与仿真输出逐拍对比。

## Step 6: 记录发现

**先写 WORKLOG，再改代码。** 记录：
- 现象是什么
- 根因是什么
- 尝试了什么方案
- 为什么选择这个方案

---

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
