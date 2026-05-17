# Three-Layer Auto-Test / 三层自动测试

> 开发者无需手动运行任何测试命令。写代码时自动测，提交时自动检，推 PR 时自动审。

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## 三层架构

| 层级 | 触发时机 | 执行内容 | 效果 |
|------|---------|---------|------|
| **L1 编辑即测** | Claude Code 编辑源码后 | vitest / jest / pytest | AI 写完立即知道测试是否通过 |
| **L2 提交即检** | `git commit` 时 | 声明式 `.pre-commit-config.yaml`，按需开关 hook | 不合格代码无法提交 |
| **L3 PR 即审** | 推送 PR 到 GitHub 时 | 3 个 AI Agent 并行分析 + 行级评论 + PR 摘要 | 安全/Bug/Style 全覆盖 |

## 安装

### 方式一：一行命令（最快）

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Markhufei/three-layer-test/master/setup.sh)
```

在你的项目根目录运行即可，自动检测项目类型并安装。

### 方式二：Claude Code 技能包

```bash
git clone https://github.com/Markhufei/three-layer-test.git \
  ~/.claude/skills/three-layer-test
```

然后在任何 Claude Code 会话中说：

```
三层自动测试-为当前项目配置全量测试
```

Claude Code 会自动执行全部安装流程。

### 方式三：手动安装

逐项创建下方文件：

```
.claude/hooks/test-on-change.sh          ← L1 脚本
.claude/settings.local.json              ← L1 配置（PostToolUse hook）
.pre-commit-config.yaml                  ← L2 声明式配置
.git/hooks/pre-commit                    ← L2 bash 回退 hook
.github/workflows/quinn-qa.yml           ← L3 Workflow
```

## v2 升级亮点

### L2 — 声明式配置

从手写 bash 脚本升级为 `.pre-commit-config.yaml`，用户可按需启用/禁用任何 hook：

```yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    hooks:
      - id: detect-private-key        # 安全：检测私钥
      - id: check-merge-conflict      # 检测未解决的合并冲突

  - repo: local
    hooks:
      - id: typecheck                 # tsc --noEmit
      - id: lint                      # eslint
      - id: test                      # vitest run
      - id: debug-scan                # 扫描 console.log / debugger
```

兼容 [pre-commit](https://github.com/pre-commit/pre-commit) 和 [prek](https://github.com/j178/prek) 框架。

### L3 — 多 Agent 并行分析

从单次 prompt 升级为 3 个并行 AI Agent：

| Agent | 关注点 | 输出 |
|-------|--------|------|
| 🛡️ Security Agent | SQL 注入、XSS、硬编码密钥、IDOR、权限绕过 | 🔴 CRITICAL / 🟡 WARNING |
| 🐛 Bug Agent | 空指针、边界条件、竞态、资源泄漏、逻辑错误 | 🔴 BUG / 🟡 CONCERN |
| 🎨 Style Agent | 命名、函数长度、重复代码、注释、魔法数字 | 🔴 ISSUE / 🟡 SUGGESTION |

**行级评论**：问题直接评论到 PR diff 的具体代码行上，类似 CodeRabbit 的体验。

## 配置 AI 模型（L3）

L3 的 AI QA Review 支持任意 Anthropic 兼容接口的模型，通过 **GitHub Repository Variables** 配置：

### 必须配置

| 类型 | 名称 | 值 |
|------|------|-----|
| Secret | `AI_API_KEY` | 你的 API Key |
| Variable | `AI_MODEL` | 模型名称，如 `qwen3.6-plus` |
| Variable | `AI_API_ENDPOINT` | API 地址 |
| Variable | `AI_API_VERSION` | API 版本，如 `2023-06-01` |

**必须在 GitHub Settings 中配置以上 4 项**，否则 L3 AI Review 不会生效。

### 常用模型配置参考

| 平台 | AI_MODEL | AI_API_ENDPOINT |
|------|----------|-----------------|
| 百炼-Coding Plan | `qwen3.6-plus` | `https://coding.dashscope.aliyuncs.com/apps/anthropic` |
| Anthropic 官方 | `claude-sonnet-4-6` | `https://api.anthropic.com/v1/messages` |
| Anthropic Opus | `claude-opus-4-7` | `https://api.anthropic.com/v1/messages` |

### 配置步骤

1. 打开仓库的 GitHub 页面
2. **Settings → Actions → Variables and secrets → Actions**
3. 在 **Repository secrets** 中添加 `AI_API_KEY`
4. 在 **Repository variables** 中添加 `AI_MODEL`、`AI_API_ENDPOINT`、`AI_API_VERSION`

## 文件结构

```
.claude/
  skills/
    three-layer-test/
      SKILL.md                    ← Claude Code 安装指令
hooks/
  test-on-change.sh               ← L1: 编辑即测脚本
templates/
  .pre-commit-config.yaml         ← L2: 声明式预提交配置
.github/
  workflows/
    quinn-qa.yml                  ← L3: GitHub Actions（多 Agent）
setup.sh                          ← 一键安装脚本
```

## 与成熟方案的关系

| 维度 | 本方案 | 业界方案 |
|------|--------|---------|
| L1 编辑即测 | Claude Code Hook，AI 改完代码立即测 | 无直接替代（场景太新） |
| L2 提交即检 | 声明式 `.pre-commit-config.yaml` | [pre-commit](https://github.com/pre-commit/pre-commit) / [Husky](https://github.com/typicode/husky) |
| L3 PR 即审 | 3 Agent 并行 + 行级评论 | [CodeRabbit](https://coderabbit.ai/) / [Qodo PR-Agent](https://github.com/The-PR-Agent/pr-agent) |

本方案的核心差异化是 L1 + 一键安装体验，L2/L3 与业界方案互补而非替代。

## License

MIT
