---
name: three-layer-test
preamble-tier: 1
version: 1.0.0
description: |
  三层全自动测试系统 — 为项目一键配置 L1 编辑即测 + L2 提交即检 + L3 PR 即审。
  用户无需手动运行任何测试命令。使用场景：为新项目或现有项目添加全生命周期测试保障。
  触发词："三层自动测试"、"three-layer-test"、"为这个项目启动三层自动测试"。
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - AskUserQuestion

---

## 概述

当用户说 **"三层自动测试-{任务目标}"** 时，为该项目的 `{任务目标}` 配置三层全自动测试：

| 层级 | 触发时机 | 执行内容 |
|------|---------|---------|
| L1 编辑即测 | Claude Code 编辑源码后 | 自动运行 vitest/jest/pytest |
| L2 提交即检 | git commit 时 | tsc + eslint + vitest + 调试代码扫描 |
| L3 PR 即审 | 推送 PR 到 GitHub 时 | Unit Tests + E2E Tests + AI QA Review |

## 第 1 步：检测项目状态

先确认当前环境：

```bash
# 检测是否在 git 仓库
git rev-parse --show-toplevel 2>/dev/null || echo "NO_GIT_REPO"
# 检测项目类型
[ -f package.json ] && echo "NODE_PROJECT" || true
[ -f pyproject.toml ] && echo "PYTHON_PROJECT" || true
[ -f go.mod ] && echo "GO_PROJECT" || true
# 检测已有测试框架
grep -q '"vitest"' package.json 2>/dev/null && echo "HAS_VITEST" || true
grep -q '"jest"' package.json 2>/dev/null && echo "HAS_JEST" || true
grep -q '"playwright"' package.json 2>/dev/null && echo "HAS_PLAYWRIGHT" || true
command -v pytest &>/dev/null && echo "HAS_PYTEST" || true
# 检测已有 hooks
[ -f .claude/settings.local.json ] && echo "HAS_CLAUDE_SETTINGS" || true
[ -f .git/hooks/pre-commit ] && echo "HAS_PRE_COMMIT_HOOK" || true
[ -d .github/workflows ] && echo "HAS_GITHUB_WORKFLOWS" || true
```

将结果汇总告知用户，说明当前项目状态。

## 第 2 步：确认配置方案

用 AskUserQuestion 向用户展示检测到的项目类型，确认要安装的层级：

- 默认 L1+L2+L3 全装
- 如果无 git 仓库，提示先初始化 git
- 如果非 GitHub 托管，L3 可跳过

**关键决策：AI QA Review 使用的模型**

默认值适用于 Anthropic 官方 API。如果用户使用其他平台，告知可在 GitHub Settings → Variables 中修改。

## 第 3 步：安装依赖

### Node.js 项目

```bash
npm install --save-dev vitest @testing-library/react @testing-library/jest-dom @playwright/test
npx playwright install chromium
```

### Python 项目

```bash
pip install pytest playwright
playwright install chromium
```

## 第 4 步：创建配置文件

### vitest.config.ts（Node.js 项目）

读取当前目录已有文件，不存在则创建：

```typescript
import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    setupFiles: ['src/test/setup.ts'],
  },
})
```

### playwright.config.ts（Node.js 项目）

```typescript
import { defineConfig, devices } from '@playwright/test'

export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: true,
  use: {
    baseURL: 'http://localhost:3000',
    trace: 'on-first-retry',
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
  ],
})
```

### src/test/setup.ts

```typescript
import '@testing-library/jest-dom/vitest'
```

## 第 5 步：创建 L1 Hook 配置

读取 `.claude/settings.local.json` 已有内容，追加 PostToolUse hook。

如果文件已存在且已有 `test-on-change` 相关 hook，跳过。否则合并：

- 读取现有 `settings.local.json`
- 在 `PostToolUse.Write` 和 `PostToolUse.Edit` 的 hooks 数组中各追加 `test-on-change.sh` 条目
- 不要覆盖已有的其他 hook 配置

hook 脚本来源：读取当前仓库 `.claude/skills/three-layer-test/hooks/test-on-change.sh`，写入项目 `.claude/hooks/test-on-change.sh`。

## 第 6 步：创建 L2 pre-commit hook

创建 `.git/hooks/pre-commit`（如已有则追加或合并，不覆盖用户现有内容）：

```bash
#!/bin/bash
# pre-commit — L2: 提交前检查

set -euo pipefail

echo "Running pre-commit checks..."

# 类型检查
echo "→ tsc --noEmit"
npx tsc --noEmit

# Lint
echo "→ eslint"
npx eslint src/

# 测试
echo "→ vitest"
npx vitest run

# 调试代码扫描
echo "→ Scanning for debug code..."
grep -rn "console\.log" src/ --include="*.ts" --include="*.tsx" --exclude="*.test.*" && {
  echo "ERROR: console.log found in source files"
  exit 1
} || true

grep -rn "debugger" src/ && {
  echo "ERROR: debugger statement found"
  exit 1
} || true

echo "All checks passed!"
```

```bash
chmod +x .git/hooks/pre-commit
```

## 第 7 步：创建 L3 GitHub Actions workflow

创建 `.github/workflows/quinn-qa.yml`（如已存在则跳过或询问用户是否覆盖）。

**关键：AI 模型可配置**，通过 GitHub Repository Variables 设置：

| Variable | 默认值 | 说明 |
|----------|--------|------|
| `AI_API_ENDPOINT` | `https://api.anthropic.com/v1/messages` | API 地址 |
| `AI_MODEL` | `claude-sonnet-4-6` | 模型名称 |
| `AI_API_VERSION` | `2023-06-01` | API 版本 |

Secret 需设置：`AI_API_KEY`

workflow 文件内容从当前仓库 `.github/workflows/quinn-qa.yml` 复制。

## 第 8 步：创建初始测试脚手架

为项目创建一个示例测试文件，验证配置正确：

```typescript
// src/example.test.ts
import { describe, it, expect } from 'vitest'

describe('project setup', () => {
  it('should pass a smoke test', () => {
    expect(true).toBe(true)
  })
})
```

## 第 9 步：验证全部通过

```bash
# 验证 L1：手动触发一次测试
npx vitest run --reporter=verbose

# 验证 L2：dry-run pre-commit
bash .git/hooks/pre-commit

# 验证文件存在性
echo "=== L1 Hook ==="
grep -c "test-on-change" .claude/settings.local.json || echo "MISSING"
echo "=== L2 Hook ==="
[ -x .git/hooks/pre-commit ] && echo "OK" || echo "MISSING"
echo "=== L3 Workflow ==="
[ -f .github/workflows/quinn-qa.yml ] && echo "OK" || echo "MISSING"
```

## 第 10 步：告知用户如何使用

### 配置 AI 模型（GitHub Variables）

打开仓库的 GitHub 页面 → Settings → Actions → Variables → Repository variables：

| 变量 | 设置值 | 示例 |
|------|--------|------|
| `AI_MODEL` | 模型名称 | `qwen3-coder-plus` / `claude-opus-4-7` / `gpt-4o` |
| `AI_API_ENDPOINT` | API 地址 | `https://coding.dashscope.aliyuncs.com/apps/anthropic/v1/messages` |
| `AI_API_VERSION` | API 版本 | `2023-06-01` |

### 配置 API 密钥（GitHub Secrets）

Settings → Secrets and variables → Actions → Repository secrets：

| Secret | 值 |
|--------|-----|
| `AI_API_KEY` | 你的 API Key |

### 常用模型配置参考

| 平台 | AI_MODEL | AI_API_ENDPOINT |
|------|----------|-----------------|
| Anthropic 官方 | `claude-sonnet-4-6` | `https://api.anthropic.com/v1/messages` |
| Anthropic Opus | `claude-opus-4-7` | `https://api.anthropic.com/v1/messages` |
| 阿里云 DashScope | `qwen3-coder-plus` | `https://coding.dashscope.aliyuncs.com/apps/anthropic/v1/messages` |
| OpenAI 兼容 | `gpt-4o` | 服务商地址 |

### 日常使用

配置完成后，开发者**无需任何操作**：

- **写代码时** → Claude Code 自动运行相关测试（L1）
- **git commit 时** → 自动运行全部检查（L2）
- **推送 PR 时** → GitHub Actions 自动运行测试 + AI 审查（L3）
