# AGENTS.md — AI 工作指南

这是由 AI 创建和维护的硬件设计项目。

## 开始前（必须）

1. 读 `ai/QUICKSTART.md` — 快速上手
2. 读 `ai/DESIGN.md` — 理解架构
3. 读 `ai/WORKLOG.md` — 了解最近改了什么
4. 读 `ai/TODO.md` — 当前待办事项
5. 运行 `make sim` — 确认当前代码是绿的
6. 如果仿真失败 → 查 `ai/BUGS.md`，按 `ai/DEBUG_GUIDE.md` 流程定位

## 修改代码时

1. **先跑** `make sim` 确认当前正确
2. **每次改一个东西**，不要批量改
3. **改完再跑** `make sim` 确认没搞坏
4. **添加新测试**（如果引入了新功能）
5. **更新 `ai/WORKLOG.md`** 记录修改（格式见下方）
6. **更新 `ai/TODO.md`** 标记完成项
7. **Commit** 按 `ai/STYLE_GUIDE.md` 规范

## 核心规则

- **仿真通过才能标 ✅** — 代码写完但没跑 → 🟡 进行中
- **有符号运算** — 所有数据用 `$signed`
- **参数化** — 所模块通过 `parameter` 支持可配置大小
- **可综合** — RTL 不用 `initial`、`#delay`
- **数据对齐** — A[i][k] 和 B[k][j] 必须在同一周期到达 PE(i,j)

## WORKLOG 记录格式

```markdown
## [日期] 简要描述

### 改动文件
- 哪些文件、做了什么

### 验证结果（必须有）
- 跑了哪些测试、结果如何
```

## 详细参考

| 主题 | 文件 |
|------|------|
| 快速上手 | `ai/QUICKSTART.md` |
| 架构设计 | `ai/DESIGN.md` |
| Debug 流程 | `ai/DEBUG_GUIDE.md` |
| 代码风格 | `ai/STYLE_GUIDE.md` |
| Bug 追踪 | `ai/BUGS.md` |
| 待办事项 | `ai/TODO.md` |
| 工作日志 | `ai/WORKLOG.md` |
| 演进路线 | `ai/PLAN.md` |
