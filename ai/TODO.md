# TODO.md — 待办事项

优先级：🔴 高  🟡 中  🟢 低

> **规则：只有仿真通过后才能标记 ✅ 完成。代码写完但未验证 → 🟡 进行中。**

---

## 🔴 高优先级 — Phase 0: 验证闭环

> 所有后续工作的前提。FEED_CYCLES bug 已修复，但新发现 Bug 1+2 导致仿真仍失败。
> 详见 `ai/BUGS.md`。

### 1. 数据对齐 bug 修复
- [x] 定位根因：A/B 到达时间差 j-i 个周期
- [x] 实施错开喂入 (staggered feeding) 方案
- [x] **修复 FEED_CYCLES 不足**（根因：`K+max(M,N)-1` 应为 `K+M+N-2`）
- [x] **修复 Bug 1**：TB 数据设置时序偏移（`tb_systolic_array.v`）(2026-04-30)
- [x] **修复 Bug 2**：`en` 信号延迟问题（通过 TB 协议修复间接解决）(2026-04-30)
- [x] **修复 Bug 3**：overflow TB 同样的时序竞态（`tb_overflow.v`）(2026-04-30)
- [x] `make sim` 默认 4×4×4 全部 PASS (2026-04-30)
- [x] `make sim M=8 K=8 N=8` 大矩阵通过 (2026-04-30)
- [x] `make sim M=3 K=5 N=7` 矩形矩阵通过 (2026-04-30)
- [x] `make sim W=16` 不同位宽通过 (2026-04-30)

### 2. 溢出测试验证
- [x] `make overflow` 通过 (2026-04-30)
- [x] 手动推演饱和逻辑正确性 (2026-04-30)
- 依赖：1

### 3. back-to-back 连续计算测试
- [x] 连续喂 3 组不同矩阵，每组结果独立正确 (2026-04-30，Test 6a/6b)
- [x] 直接 DONE→FEED 不经 IDLE 的 back-to-back 通过 (2026-05-01，tb_bug_verify Bug 1)
- 依赖：1

### 4. 边界值测试
- [x] 全零矩阵 → 结果全零 (2026-04-30)
- [x] 单位矩阵 → A×I = A (已通过 Test 3)
- [x] 1×1 × 1×1 最小尺寸 (2026-04-30)
- [ ] 全最大值/全最小值 → 检查饱和（已通过 overflow 测试覆盖）
- [ ] 依赖：1

---

## 🟡 中优先级 — Phase 1: 补短板（待 Phase 0 完成后）

### 5. 溢出检测与饱和运算
- [x] 代码实现（pe.v 增加溢出检测和饱和逻辑）
- [ ] **仿真验证**（标记为完成前必须跑通）
- 状态：🟡 进行中

### 6. 结果保持与读出接口
- [x] 代码实现（result_bank + row_sel/col_sel）
- [ ] **仿真验证**
- 状态：🟡 进行中

### 7. 状态与错误输出
- [x] 代码实现（cycle_count, overflow_count）
- [ ] **仿真验证**
- 状态：🟡 进行中

### 8. PE 传递门控修复
- [x] 代码实现（a_out/b_out 解耦 en 信号）
- [ ] **仿真验证**
- 状态：🟡 进行中

### 9. en 信号改为寄存器输出
- [ ] `en` 从 `state == S_FEED` 组合逻辑改为 `state_next == S_FEED` 寄存器输出
- [ ] 同时解决 Bug 2（en 比状态转移晚 1 拍）
- [ ] 降低扇出压力（M×N 个 PE 共享同一组合比较器 → 寄存器驱动）
- ⚠️ 改动需同步调整 FEED_CYCLES 和边界逻辑（Bug 11/12 分析结论），风险较大
- 依赖：Phase 0

### 10. `$clog2(1)` 零宽度端口修复（Bug 4）
- [x] `row_sel` / `col_sel` 端口位宽保护：`$clog2(N) > 0 ? $clog2(N) : 1`
- [x] 增加 M=1 的测试用例验证修复 (2026-04-30)
- 依赖：Phase 0

### 11. 累加器清零时机优化
- [ ] `clear_acc` 从 IDLE/DONE 持续拉高改为仅 IDLE→FEED 转换周期清零一次
- [ ] 避免 DONE 等待期间累加器被持续清零、无法开始下一次计算
- 依赖：Phase 0

### 12. overflow 标志独立清零
- [ ] 增加独立的 `clear_overflow` 信号，不与 `clear_acc` 耦合
- [ ] 支持连续计算中保留上一轮溢出信息
- [ ] 或将 overflow 移入 result_bank 一起锁存
- 依赖：Phase 0

### 13. 结果读出去掉二维数组端口
- [ ] 去掉 `c_data [0:M_ROWS-1][0:N_COLS-1]` 全矩阵直连端口
- [ ] 只保留 `result_bank` + `row_sel/col_sel` 地址读出
- [ ] 或改为一维 flatten 输出，提升综合工具兼容性（Vivado 对 unpacked array 支持差）
- 依赖：Phase 0

### 14. 边界逻辑代码去重
- [ ] A/B 边界逻辑抽取为通用 boundary logic 模块或 generate 封装
- [ ] 减少重复代码，便于维护
- 依赖：Phase 0

---

## 🟡 中优先级 — Phase 2: 工程化

### 15. Verilator Lint 检查
- [ ] 安装 Verilator
- [ ] `verilator --lint-only -Wall src/*.v` 零 warning
- [ ] Makefile 新增 `make lint`
- 依赖：Phase 0

### 16. 回归测试脚本
- [ ] `scripts/regression.sh` 跑全尺寸组合（M/K/N: 1,2,4,8,16 × W: 4,8,16）
- [ ] 生成汇总报告
- [ ] 集成到 Makefile：`make regression`
- 依赖：Phase 0

### 17. GitHub Actions CI
- [ ] `.github/workflows/ci.yml`
- [ ] push 自动跑 lint + sim + regression
- 依赖：15, 16

### 18. Makefile 增强
- [ ] `make lint` — Verilator 静态检查
- [ ] `make regression` — 全尺寸回归
- [ ] `make all` — lint + sim + overflow
- [ ] `make help` 内容扩充
- [ ] 去掉 sed 参数替换方式，改用 iverilog `-P` 或 `` `define `` 传递参数
- 依赖：15, 16

### 19. 测试覆盖率补全
- [ ] 负数乘法专项测试（`-3 × 5 = -15`）
- [ ] 零矩阵测试（全零 → 结果全零）
- [ ] 极端尺寸测试（1×1 / 1×N / M×1）
- [ ] 不同 K_DIM 矩形测试（K ≠ M ≠ N）
- [ ] 连续溢出测试（多次计算后 overflow 标志累积）
- [ ] reset 测试（计算中途拉低 rst_n）
- [ ] 协议检查：`c_valid` 是否在正确周期断言
- 依赖：Phase 0

### 20. Cocotb (Python) 测试平台
- [ ] `pip install cocotb`
- [ ] `tests/test_basic.py`：基本矩阵乘法 + numpy 对比
- [ ] `tests/test_overflow.py`：溢出饱和
- [ ] `tests/test_random.py`：随机矩阵 + numpy 自动对比
- [ ] `tests/test_boundary.py`：边界值
- [ ] Makefile 新增 `make cocotb`
- 优势：参数化更自然、断言信息更清晰、可做覆盖率收集
- 依赖：Phase 0

---

## 🟢 低优先级 — Phase 3: RTL 优化

### 21. PE 流水线化
- [ ] 乘法和累加拆成两级流水线（product_reg + accum）
- [ ] 提高最大时钟频率（尤其 DATA_WIDTH>8 时）
- [ ] 代价：每 PE 多 1 拍延迟，FEED_CYCLES 需调整
- 依赖：Phase 0

### 22. 双缓冲 (Double Buffering)
- [ ] 两组输入缓冲交替切换
- [ ] 一组在计算，另一组同时加载
- [ ] DONE→FEED 零间隙切换，消除加载等待
- [ ] 依赖：Phase 0

### 23. 性能计数器增强
- [ ] `active_pe_cycles`：PE 实际做乘累加的周期数
- [ ] `total_cycles`：start→done 总周期数
- [ ] `pe_utilization` = active_pe_cycles / (M×N×total_cycles)
- [ ] `throughput_gops` = (2×M×N×K) / (total_cycles × clock_period)
- 依赖：Phase 0

### 24. 时钟门控 (Clock Gating)
- [ ] 空闲行/列关闭时钟
- [ ] 降低动态功耗
- 依赖：Phase 0

---

## 🟢 低优先级 — Phase 4: 接口与系统集成

### 25. Backpressure 机制
- [ ] `a_ready` / `b_ready` 支持 FEED 阶段暂停
- [ ] `feed_cnt` 冻结，数据不丢失
- 依赖：Phase 0

### 26. AXI-Stream 数据接口
- [ ] `src/axi_stream_wrapper.v`
- [ ] Slave 接收 A/B，Master 发送 C
- [ ] 支持 tvalid/tready/tlast
- 依赖：25

### 27. AXI-Lite 配置接口
- [ ] 运行时寄存器配置矩阵大小、模式、状态
- [ ] 寄存器映射：CTRL/STATUS/DIM_M/DIM_K/DIM_N/MODE/CYCLE_COUNT/OVFLOW_COUNT
- 依赖：26

### 28. 中断支持
- [ ] 计算完成、溢出事件触发 IRQ
- [ ] 中断状态/使能寄存器
- 依赖：27

### 29. 串行输入模式
- [ ] 支持窄带宽输入（每周期 1 个元素而非 M/N 个）
- [ ] 内部缓冲 + 串并转换
- [ ] 降低外部接口宽度需求
- 依赖：Phase 0

---

## 🟢 低优先级 — Phase 5: 高级数据类型

### 30. 定点数支持 (Fixed-Point)
- [ ] Q 格式定点数（Q8.8、Q4.12、Q16.16）
- [ ] PE 增加 `FRAC_BITS` 参数
- 依赖：Phase 0

### 31. 半精度浮点 (FP16)
- [ ] FP16 MAC 单元替换 PE 内整数乘累加
- [ ] 乘法器 + 加法器 + 舍入逻辑
- 依赖：Phase 0

### 32. BFloat16 支持
- [ ] 指数 8-bit、尾数 7-bit，硬件比 FP16 更简单
- 依赖：31

### 33. 混合精度模式
- [ ] INT8 输入 × FP16 累加
- [ ] INT4 输入 × INT8 累加
- [ ] 量化推理常用组合
- 依赖：30, 31

---

## 🟢 低优先级 — Phase 6: 功能扩展

### 34. 转置模式
- [ ] 支持 A×B / Aᵀ×B / A×Bᵀ / Aᵀ×Bᵀ 四种模式
- [ ] 增加 `transpose_mode` 配置信号
- 依赖：Phase 0

### 35. 矩阵加法模式
- [ ] 复用 PE 阵列做 element-wise C = A + B
- [ ] PE 增加 `mode` 选择（MAC / ADD）
- 依赖：Phase 0

### 36. 向量-矩阵乘法
- [ ] y = v × M（1×K 向量 × K×N 矩阵）
- [ ] 只用第一行 PE，其余行旁路
- 依赖：Phase 0

### 37. 权重驻留模式 (Weight Stationary)
- [ ] B 矩阵预加载到 PE 寄存器，只流式输入 A
- [ ] 用途：CNN 推理、Transformer 注意力
- [ ] PE 增加 weight_reg + weight_load 模式
- 依赖：Phase 0, 22

### 38. 分块计算 (Tiling)
- [ ] 大矩阵自动拆分成阵列能处理的小块
- [ ] 上层 wrapper 负责分块、调度、结果拼接
- 依赖：37

---

## 🟢 低优先级 — Phase 7: 应用层

### 39. CNN 推理加速器
- [ ] im2col → 脉动阵列乘法 → 加偏置 → ReLU
- [ ] 新建 im2col.v / bias_add.v / relu.v / cnn_layer.v
- 依赖：37, 26

### 40. Transformer 注意力加速
- [ ] Attention(Q,K,V) = softmax(Q×Kᵀ/√d) × V
- [ ] 权重驻留 + 分块计算
- 依赖：37, 38, 31

### 41. 矩阵分解加速
- [ ] LU/QR/Cholesky 分解
- [ ] 上层状态机调度多次矩阵乘法
- 依赖：36, 38

---

## 🟢 低优先级 — Phase 8: FPGA 综合与上板

### 42. Xilinx Vivado 综合
- [ ] `scripts/vivado_build.tcl`
- [ ] 约束文件 `constraints/timing.xdc`
- [ ] 资源利用率 / 时序 / 功耗报告
- 依赖：15

### 43. Intel Quartus 综合
- [ ] `scripts/quartus_build.tcl`
- 依赖：15

### 44. 资源与时序分析报告
- [ ] 不同阵列大小 × 不同 FPGA 器件 × 不同位宽对比
- [ ] 输出：`docs/fpga_benchmark.md`
- 依赖：42

### 45. 上板验证
- [ ] UART 喂数据 + 串口出结果
- [ ] 新建 uart_rx.v / uart_tx.v / top_fpga.v
- 依赖：42, 26

---

## 🔴 高优先级 — Phase 9: 文档与工作流优化

> 当前 6 个文档（AGENTS/DESIGN/WORKLOG/TODO/PLAN/BUGS）职责重叠严重，
> 同一信息多处记录、状态不同步。需要一次性整理清楚。

### 46. 文档职责去重
- [x] **DESIGN.md** = 架构决策（只写"为什么"和"是什么"）(2026-04-29)
- [x] **BUGS.md** = bug 状态追踪（唯一真相源，含复现步骤）(2026-04-29)
- [x] **TODO.md** = 待办清单（只列任务，不重复 bug 细节）
- [x] **PLAN.md** = 长期路线图（只列里程碑和依赖，不列具体任务，与 TODO 合并或明确分工）
- [x] **WORKLOG.md** = 历史记录（只写"做了什么"，格式严格统一：改动文件 + 验证结果）(2026-04-29)
- [x] **AGENTS.md** = 工作流程规范（只写规则，不写项目具体内容）(2026-04-29)
- [x] 删除各文档间的重复段落，改为交叉引用 (2026-04-29)

### 47. DESIGN.md / README.md 信息纠错
- [x] README 时序示例 off-by-one（4×4×4 的 feed_cnt 应为 0~9，不是 0~7）(2026-04-29)
- [x] DESIGN.md ACCUM_WIDTH 建议与 Makefile 默认值不一致（`2*W+clog2(K)` vs `4*W`）(2026-04-29)
- [x] 统一所有文档中的时序描述，单一真相源 (2026-04-29)

### 48. BUGS.md 增加复现步骤
- [x] 每个 bug 增加 `make sim` 复现命令和期望/实际输出 (2026-04-29)
- [x] 新 AI 进来能直接验证 bug 是否还存在 (2026-04-29)

### 49. AGENTS.md 精简 + 拆分
- [x] AGENTS.md 精简到 50 行：核心规则 + 优先级 (2026-04-29)
- [x] 拆出 `ai/DEBUG_GUIDE.md`：debug 流程 + 常见陷阱（需要时才读）(2026-04-29)
- [x] 拆出 `ai/STYLE_GUIDE.md`：commit 规范 + 代码风格（需要时才读）(2026-04-29)

### 50. 增加 QUICKSTART.md
- [x] 一页纸：项目是什么（3 句话）+ 文件结构（一图）+ 开始前跑什么 + 改完后跑什么 (2026-04-29)
- [x] 指向其他文档的详细信息链接 (2026-04-29)
- [x] 新 AI / 新开发者 5 分钟上手 (2026-04-29)

---

## 🟡 中优先级 — Phase 10: 开发实践优化

### 51. Pre-commit hook
- [x] `.git/hooks/pre-commit`：commit 前自动跑 `make sim` (2026-04-29)
- [x] 仿真失败则拒绝 commit (2026-04-29)
- [x] 防止"改了代码忘了跑仿真就 commit" (2026-04-29)

### 52. Commit 粒度规范
- [x] 一个 commit 一个逻辑变更（不混 RTL 修复 + 文档更新）(2026-04-29)
- [x] 在 STYLE_GUIDE.md 中明确规范 (2026-04-29)
- [x] 示例：`fix: PE a_out/b_out 解耦` 和 `fix: tb_overflow 补全端口` 分开提交 (2026-04-29)

### 53. Branch 策略
- [x] `main` = 稳定版本，仿真全部通过 (2026-04-29)
- [x] `fix/*` = bug 修复分支 (2026-04-29)
- [x] `feat/*` = 新功能分支 (2026-04-29)
- [x] `docs/*` = 文档分支 (2026-04-29)
- [x] 修完测完再合入 main (2026-04-29)

### 54. Makefile 去 sed 改 -D
- [x] 去掉脆弱的 `sed` 参数替换 (2026-04-29)
- [x] 改用 `iverilog -DM_ROWS=$(M) -DK_DIM=$(K) ...` (2026-04-29)
- [x] TB 中用 `` `ifdef `` / `` `define `` 接收参数 (2026-04-29)
- [x] 避免 TB 代码格式变化导致 sed 失效 (2026-04-29)

### 55. Python 脚本统一入口
- [x] 合并 `scripts/` 下独立脚本为统一入口 (2026-04-29)
- [x] `python3 scripts/sim.py sim|debug|verify|sizes` (2026-04-29)

### 56. .editorconfig
- [x] 统一 Verilog 代码格式：4 空格缩进、LF 换行 (2026-04-29)
- [x] 避免混合 tab/空格 (2026-04-29)

---

## 已完成

- [x] 基础 PE 模块实现 (2026-04-29)
- [x] 脉动阵列顶层实现 (2026-04-29)
- [x] FSM 控制器 (2026-04-29)
- [x] 参数化设计 (2026-04-29)
- [x] 基础测试平台 (2026-04-29)
- [x] Makefile 和仿真脚本 (2026-04-29)
- [x] AI 协作基础设施 (2026-04-29)
