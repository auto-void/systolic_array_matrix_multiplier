# STYLE_GUIDE.md — 代码风格与 Commit 规范

## Commit Message 规范

格式：`type: 简要描述`

| type | 用途 |
|------|------|
| `feat` | 新功能 |
| `fix` | Bug 修复 |
| `refactor` | 重构（不改变功能） |
| `test` | 测试相关 |
| `docs` | 文档更新 |
| `perf` | 性能优化 |
| `chore` | 构建/工具/杂项 |

**规则**：
- 一个 commit 一个逻辑变更
- 不混 RTL 修改 + 文档更新（分开提交）
- 描述用中文或英文，保持一致

**示例**：
```
fix: PE a_out/b_out 解耦 en 信号
docs: 修正 README 时序示例 off-by-one
test: 增加负数乘法专项测试
```

## Verilog 代码风格

### 缩进与格式
- 4 空格缩进，不用 tab
- `begin` 放在同一行，`end` 独占一行
- 模块端口声明每行一个

### 命名
- 模块名：`snake_case`（如 `systolic_array`）
- 信号名：`snake_case`（如 `feed_cnt`、`pe_a_in`）
- 参数名：`UPPER_CASE`（如 `M_ROWS`、`DATA_WIDTH`）
- generate 标签：`gen_` 前缀（如 `gen_row`、`gen_a_boundary`）

### 注释
- 每个模块顶部：功能描述 + 端口说明
- 关键逻辑：行内注释解释"为什么"，而非"是什么"
- 过时注释立即删除，不留隐患

### 可综合约束
- RTL 不用 `initial`、`#delay`、`$display`
- Testbench 可以用
- 组合逻辑用 `assign` 或 `always @(*)`
- 时序逻辑用 `always @(posedge clk or negedge rst_n)`

## Branch 策略

```
main          ← 稳定版本，仿真全部通过
├── fix/*     ← bug 修复分支（如 fix/bug1-tb-timing）
├── feat/*    ← 新功能分支（如 feat/pe-pipeline）
└── docs/*    ← 文档分支（如 docs/workflow-cleanup）
```

**规则**：
- `main` 分支必须始终能通过 `make sim`
- 不直接在 main 上修 bug 或加功能
- 修完、测完再合入 main
- 合入前确认 `make sim` 通过
