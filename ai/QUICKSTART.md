# QUICKSTART.md — 快速上手

## 这个项目是什么

可配置大小的**脉动阵列矩阵乘法器**（Systolic Array Matrix Multiplier）。
Verilog RTL 设计，支持任意 M×K × K×N 有符号整数矩阵乘法，Icarus Verilog 仿真验证。

## 文件结构

```
src/                  ← RTL 源码
  pe.v                ← 处理单元（MAC + 溢出饱和 + 数据传递）
  systolic_array.v    ← 顶层阵列（FSM + 边界逻辑 + PE 阵列）
  systolic_array_top.v← 可配置包装
tb/                   ← 测试平台
  tb_systolic_array.v ← 主测试（6 个测试用例）
  tb_overflow.v       ← 溢出饱和测试
ai/                   ← AI 协作文档（遇到问题先查这里）
scripts/              ← 辅助脚本
Makefile              ← 构建系统
```

## 开始前（必须）

```bash
# 1. 确认仿真器可用
iverilog -V

# 2. 跑仿真，确认当前代码是绿的
make sim

# 3. 如果失败 → 去 ai/BUGS.md 看已知问题，去 ai/WORKLOG.md 看最近改了什么
```

## 改完代码后（必须按顺序）

```bash
# 1. 跑仿真确认没搞坏
make sim

# 2. 跑不同尺寸（如果改了数据流）
make sim M=2 K=2 N=2
make sim M=3 K=5 N=7

# 3. 跑溢出测试（如果改了 PE）
make overflow

# 4. 更新文档
#    - ai/WORKLOG.md 顶部加一条记录（改了什么、验证结果）
#    - ai/TODO.md 标记完成的项目（仿真通过才能标 ✅）

# 5. Commit
git add -A && git commit -m "type: 描述"
# type: feat / fix / refactor / test / docs / perf
```

## 遇到问题

| 问题 | 去哪看 |
|------|--------|
| 仿真失败 | `ai/BUGS.md` — 已知 bug 列表 |
| 不理解架构 | `ai/DESIGN.md` — 数据流、模块设计、时序 |
| 不知道做什么 | `ai/TODO.md` — 待办事项和优先级 |
| 需要 debug | `ai/DEBUG_GUIDE.md` — debug 流程和常见陷阱 |
| 想了解历史 | `ai/WORKLOG.md` — 之前 AI 做了什么 |
| 长期规划 | `ai/PLAN.md` — 演进路线图 |

## 关键参数

```bash
make sim                    # 默认 4×4×4, 8-bit
make sim M=8 K=8 N=8       # 大矩阵
make sim M=3 K=5 N=7       # 矩形矩阵
make sim W=16              # 16-bit 位宽
make overflow              # 溢出测试（4-bit, 8-bit accum）
make wave                  # 打开 GTKWave 看波形
```

## 核心规则

1. **仿真通过才能标 ✅** — 代码写完但没跑 → 🟡 进行中
2. **每次改一个东西** — 不要批量改，方便定位问题
3. **先跑仿真再改代码** — 确认当前是绿的
4. **改完再跑一次** — 确认没搞坏
5. **写 WORKLOG** — 你的修改记录是下一个 AI 的上下文
