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
- [ ] **修复 Bug 1**：TB 数据设置时序偏移 1 周期（`tb_systolic_array.v`）
- [ ] **修复 Bug 2**：`en` 信号延迟 1 周期（`systolic_array.v`）
- [ ] `make sim` 默认 4×4×4 全部 PASS
- [ ] `make sim M=8 K=8 N=8` 大矩阵通过
- [ ] `make sim M=3 K=5 N=7` 矩形矩阵通过
- [ ] `make sim W=16` 不同位宽通过

### 2. 溢出测试验证
- [ ] `make overflow` 通过
- [ ] 手动推演饱和逻辑正确性
- [ ] 依赖：1

### 3. back-to-back 连续计算测试
- [ ] 连续喂 3 组不同矩阵，每组结果独立正确
- [ ] 依赖：1

### 4. 边界值测试
- [ ] 全零矩阵 → 结果全零
- [ ] 单位矩阵 → A×I = A
- [ ] 全最大值/全最小值 → 检查饱和
- [ ] 1×1 × 1×1 最小尺寸
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

---

## 🟡 中优先级 — Phase 2: 工程化

### 9. Verilator Lint 检查
- [ ] 安装 Verilator
- [ ] `verilator --lint-only -Wall src/*.v` 零 warning
- [ ] Makefile 新增 `make lint`
- 依赖：Phase 0

### 10. 回归测试脚本
- [ ] `scripts/regression.sh` 跑全尺寸组合
- [ ] 生成汇总报告
- 依赖：Phase 0

### 11. GitHub Actions CI
- [ ] `.github/workflows/ci.yml`
- [ ] push 自动跑 lint + sim
- 依赖：9, 10

### 12. Makefile 增强
- [ ] `make lint` / `make regression` / `make clean` / `make help`
- 依赖：9, 10

---

## 🟢 低优先级（Phase 3+ 按需推进）

### 13. 性能优化
- [ ] 双缓冲 (Double Buffering)
- [ ] PE 内部流水线化
- [ ] 性能计数器增强

### 14. 接口增强
- [ ] AXI-Stream 输入输出
- [ ] AXI-Lite 配置接口
- [ ] 中断支持

### 15. 大矩阵支持
- [ ] 分块计算 (tiling)
- [ ] 片上缓存 (SRAM)
- [ ] DMA 控制器集成

### 16. 浮点支持
- [ ] IEEE 754 FP16
- [ ] BFloat16
- [ ] 定点数 (Fixed-point)

### 17. FPGA 综合
- [ ] Vivado 综合脚本
- [ ] Quartus 综合脚本
- [ ] 资源利用率报告

### 18. 验证增强
- [ ] Cocotb (Python) 测试平台
- [ ] UVM 验证环境
- [ ] 覆盖率收集

---

## 已完成

- [x] 基础 PE 模块实现 (2026-04-29)
- [x] 脉动阵列顶层实现 (2026-04-29)
- [x] FSM 控制器 (2026-04-29)
- [x] 参数化设计 (2026-04-29)
- [x] 基础测试平台 (2026-04-29)
- [x] Makefile 和仿真脚本 (2026-04-29)
- [x] AI 协作基础设施 (2026-04-29)
