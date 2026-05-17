# Three-Layer Auto-Test / 三层自动测试

> 开发者无需手动运行任何测试命令。写代码时自动测，提交时自动检，推 PR 时自动审。

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## 三层架构

| 层级 | 触发时机 | 执行内容 | 效果 |
|------|---------|---------|------|
| **L1 编辑即测** | Claude Code 编辑源码后 | vitest / jest / pytest | 写完代码就知道测试是否通过 |
| **L2 提交即检** | `git commit` 时 | tsc + eslint + vitest + 调试代码扫描 | 不合格代码无法提交 |
| **L3 PR 即审** | 推送 PR 到 GitHub 时 | Unit Tests + E2E Tests + AI QA Review | 自动在 PR 下贴 QA 报告 |

## 安装

### 方式一：Claude Code 技能包（推荐）

将本仓库克隆为 Claude Code 技能包：

```bash
# 克隆到你的 Claude Code skills 目录
git clone https://github.com/Markhufei/three-layer-test.git \
  ~/.claude/skills/three-layer-test
```

然后在任何 Claude Code 会话中说：

```
三层自动测试-为当前项目配置全量测试
```

Claude Code 会自动执行全部 10 步安装流程。

### 方式二：一键脚本

```bash
# 在你的项目根目录运行
git clone https://github.com/Markhufei/three-layer-test.git /tmp/three-layer-test
bash /tmp/three-layer-test/setup.sh
```

### 方式三：手动安装

逐项创建下方文件：

```
.claude/hooks/test-on-change.sh          ← L1 脚本
.claude/settings.local.json              ← L1 配置（PostToolUse hook）
.git/hooks/pre-commit                    ← L2 脚本
.github/workflows/quinn-qa.yml           ← L3 Workflow
```

详细配置见 [SKILL.md](.claude/skills/three-layer-test/SKILL.md) 第 3-8 步。

## 配置 AI 模型（L3）

L3 的 AI QA Review 支持任意 Anthropic 兼容接口的模型，通过 **GitHub Repository Variables** 配置：

### 必须配置的 Secret

| Secret | 说明 |
|--------|------|
| `AI_API_KEY` | 你的 API Key |

### 可选配置 Variables（有合理默认值）

| Variable | 默认值 | 说明 |
|----------|--------|------|
| `AI_MODEL` | `claude-sonnet-4-6` | 模型名称 |
| `AI_API_ENDPOINT` | `https://api.anthropic.com/v1/messages` | API 地址 |
| `AI_API_VERSION` | `2023-06-01` | API 版本 |

### 常用模型配置

| 平台 | AI_MODEL | AI_API_ENDPOINT |
|------|----------|-----------------|
| Anthropic 官方（默认） | `claude-sonnet-4-6` | `https://api.anthropic.com/v1/messages` |
| Anthropic Opus | `claude-opus-4-7` | `https://api.anthropic.com/v1/messages` |
| 阿里云 DashScope | `qwen3-coder-plus` | `https://coding.dashscope.aliyuncs.com/apps/anthropic/v1/messages` |
| 其他兼容接口 | 模型名 | 对应 URL |

只要目标 API 支持 Anthropic 格式的 request（`x-api-key` + `anthropic-version` header），即可直接切换。

### 配置步骤

1. 打开仓库的 GitHub 页面
2. **Settings → Actions → Variables and secrets → Actions**
3. 在 **Repository secrets** 中点击 `New repository secret`，添加 `AI_API_KEY`
4. 在 **Repository variables** 中添加 `AI_MODEL`、`AI_API_ENDPOINT`（可选，默认值可用）

## 文件结构

```
.claude/
  skills/
    three-layer-test/
      SKILL.md                    ← Claude Code 安装指令（10步）
hooks/
  test-on-change.sh               ← L1: 编辑即测脚本（独立版，无外部依赖）
.github/
  workflows/
    quinn-qa.yml                  ← L3: GitHub Actions workflow（模型可配置）
setup.sh                          ← 一键安装脚本
```

## 技术细节

### L1 智能匹配

- 编辑 `src/math.ts` → 自动运行 `vitest run math`（按文件名匹配）
- 30 秒全局防抖，同一项目 10 秒防抖
- 日志写入 `.three-layer-test.log`，不阻塞 Claude Code

### L2 pre-commit

- `tsc --noEmit` 类型检查失败 → 拒绝提交
- `eslint` lint 失败 → 拒绝提交
- `vitest run` 测试失败 → 拒绝提交
- 检测到 `console.log` / `debugger` → 拒绝提交

### L3 GitHub Actions

```
PR 推送 → unit-tests → e2e-tests → ai-qa-review → 自动评论到 PR
```

AI Review 会分析：
- PR diff（前后 200 行）
- tsc / eslint / debug code 扫描结果
- 按严重程度分类问题（🔴/🟡/🟢）
- 最终输出 VERDICT: PASS / FAIL

## License

MIT
