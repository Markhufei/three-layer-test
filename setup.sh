#!/bin/bash
# setup.sh — 一键安装三层自动测试
# 用法: bash setup.sh 或 npx create-three-layer-test

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }

echo "========================================="
echo "  Three-Layer Auto-Test Setup"
echo "========================================="
echo ""

# === 检查前置条件 ===
info "检测项目状态..."

if ! command -v git &>/dev/null; then
  error "git 未安装，请先安装 git"
  exit 1
fi

if [ ! -d "$PROJECT_ROOT/.git" ]; then
  warn "当前目录不是 git 仓库"
  read -p "是否初始化 git 仓库？(y/N) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    git init
    success "已初始化 git 仓库"
  else
    error "需要 git 仓库才能安装 L2 (pre-commit hook)"
    exit 1
  fi
fi

# === 检测项目类型 ===
PROJECT_TYPE=""
if [ -f "$PROJECT_ROOT/package.json" ]; then
  PROJECT_TYPE="node"
  info "检测到 Node.js 项目"
elif [ -f "$PROJECT_ROOT/pyproject.toml" ]; then
  PROJECT_TYPE="python"
  info "检测到 Python 项目"
elif [ -f "$PROJECT_ROOT/go.mod" ]; then
  PROJECT_TYPE="go"
  info "检测到 Go 项目"
else
  warn "未检测到已知项目类型（需要 package.json / pyproject.toml / go.mod）"
  echo "继续安装 L1/L2 基础层？测试框架需手动配置。"
  read -p "是否继续？(y/N) " -n 1 -r
  echo
  [[ $REPLY =~ ^[Yy]$ ]] || exit 0
fi

# === 1. 安装依赖 ===
if [ "$PROJECT_TYPE" = "node" ]; then
  info "安装测试依赖..."
  cd "$PROJECT_ROOT"

  if ! grep -q '"vitest"' package.json 2>/dev/null; then
    npm install --save-dev vitest
    success "已安装 vitest"
  else
    info "vitest 已安装，跳过"
  fi

  if ! grep -q '"@playwright/test"' package.json 2>/dev/null; then
    npm install --save-dev @playwright/test
    success "已安装 playwright"
    npx playwright install chromium
    success "已安装 Chromium"
  else
    info "playwright 已安装，跳过"
  fi
fi

# === 2. 创建配置文件 ===
info "创建测试配置..."

if [ "$PROJECT_TYPE" = "node" ]; then
  if [ ! -f "$PROJECT_ROOT/vitest.config.ts" ]; then
    cat > "$PROJECT_ROOT/vitest.config.ts" << 'VITEOF'
import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    setupFiles: ['src/test/setup.ts'],
  },
})
VITEOF
    success "已创建 vitest.config.ts"
  else
    info "vitest.config.ts 已存在，跳过"
  fi

  if [ ! -f "$PROJECT_ROOT/playwright.config.ts" ]; then
    cat > "$PROJECT_ROOT/playwright.config.ts" << 'PWEOF'
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
PWEOF
    success "已创建 playwright.config.ts"
  else
    info "playwright.config.ts 已存在，跳过"
  fi

  mkdir -p "$PROJECT_ROOT/src/test"
  if [ ! -f "$PROJECT_ROOT/src/test/setup.ts" ]; then
    echo "import '@testing-library/jest-dom/vitest'" > "$PROJECT_ROOT/src/test/setup.ts"
    success "已创建 src/test/setup.ts"
  fi
fi

# === 3. 安装 L1 Hook ===
info "安装 L1 编辑即测 Hook..."

mkdir -p "$PROJECT_ROOT/.claude/hooks"
cp "$SCRIPT_DIR/hooks/test-on-change.sh" "$PROJECT_ROOT/.claude/hooks/test-on-change.sh"
chmod +x "$PROJECT_ROOT/.claude/hooks/test-on-change.sh"
success "已安装 test-on-change.sh → .claude/hooks/"

# 配置 settings.local.json
SETTINGS_FILE="$PROJECT_ROOT/.claude/settings.local.json"

HOOK_ENTRY='{
          "type": "command",
          "command": ".claude/hooks/test-on-change.sh",
          "timeout": 30,
          "statusMessage": "Running tests...",
          "async": true
        }'

if [ ! -f "$SETTINGS_FILE" ]; then
  cat > "$SETTINGS_FILE" << SEOF
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write",
        "hooks": [
          $HOOK_ENTRY
        ]
      },
      {
        "matcher": "Edit",
        "hooks": [
          $HOOK_ENTRY
        ]
      }
    ]
  }
}
SEOF
  success "已创建 .claude/settings.local.json (L1 Hook)"
else
  # 检查是否已有 test-on-change hook
  if grep -q "test-on-change" "$SETTINGS_FILE" 2>/dev/null; then
    info "L1 Hook 已存在，跳过"
  else
    # 简单追加：在 PostToolUse 数组中添加 hook
    info "追加 L1 Hook 到现有配置..."
    python3 -c "
import json, sys

with open('$SETTINGS_FILE', 'r') as f:
    config = json.load(f)

if 'hooks' not in config:
    config['hooks'] = {}

entry = {
    'type': 'command',
    'command': '.claude/hooks/test-on-change.sh',
    'timeout': 30,
    'statusMessage': 'Running tests...',
    'async': True
}

if 'PostToolUse' not in config['hooks']:
    config['hooks']['PostToolUse'] = [
        {'matcher': 'Write', 'hooks': [entry]},
        {'matcher': 'Edit', 'hooks': [entry]}
    ]
else:
    for rule in config['hooks']['PostToolUse']:
        if rule.get('matcher') in ('Write', 'Edit', '*'):
            existing_cmds = [h.get('command', '') for h in rule.get('hooks', [])]
            if not any('test-on-change' in c for c in existing_cmds):
                rule['hooks'].append(entry)

with open('$SETTINGS_FILE', 'w') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
print('Hook appended')
"
    success "L1 Hook 已追加到 settings.local.json"
  fi
fi

# === 4. 安装 L2 pre-commit hook ===
info "安装 L2 提交即检 Hook..."

PRE_COMMIT="$PROJECT_ROOT/.git/hooks/pre-commit"

if [ -f "$PRE_COMMIT" ]; then
  if grep -q "三层自动测试" "$PRE_COMMIT" 2>/dev/null || grep -q "pre-commit.*tsc" "$PRE_COMMIT" 2>/dev/null; then
    info "pre-commit hook 已存在，跳过"
  else
    warn ".git/hooks/pre-commit 已存在但内容不同，请手动合并"
  fi
else
  if [ "$PROJECT_TYPE" = "node" ]; then
    cat > "$PRE_COMMIT" << 'PCEOF'
#!/bin/bash
# pre-commit — L2: 提交前检查 (三层自动测试)

set -euo pipefail

echo "========================================="
echo "  Running pre-commit checks..."
echo "========================================="

cd "$(git rev-parse --show-toplevel)"

# 类型检查
echo "→ tsc --noEmit"
npx tsc --noEmit || { echo "ERROR: Type check failed"; exit 1; }

# Lint
echo "→ eslint"
npx eslint src/ || { echo "ERROR: Lint failed"; exit 1; }

# 测试
echo "→ vitest"
npx vitest run || { echo "ERROR: Tests failed"; exit 1; }

# 调试代码扫描
echo "→ Scanning for debug code..."
DEBUG_FOUND=false
if grep -rn "console\.log" src/ --include="*.ts" --include="*.tsx" --exclude="*.test.*" 2>/dev/null; then
  echo "ERROR: console.log found in source files"
  DEBUG_FOUND=true
fi
if grep -rn "debugger" src/ --include="*.ts" --include="*.tsx" 2>/dev/null; then
  echo "ERROR: debugger statement found"
  DEBUG_FOUND=true
fi
if [ "$DEBUG_FOUND" = true ]; then
  exit 1
fi

echo "========================================="
echo "  All checks passed!"
echo "========================================="
PCEOF
  elif [ "$PROJECT_TYPE" = "python" ]; then
    cat > "$PRE_COMMIT" << 'PCEOF'
#!/bin/bash
# pre-commit — L2: 提交前检查 (三层自动测试)

set -euo pipefail

echo "Running pre-commit checks..."
cd "$(git rev-parse --show-toplevel)"

echo "→ flake8"
flake8 src/ || { echo "ERROR: Lint failed"; exit 1; }

echo "→ pytest"
pytest -x || { echo "ERROR: Tests failed"; exit 1; }

echo "All checks passed!"
PCEOF
  fi
  chmod +x "$PRE_COMMIT"
  success "已创建 .git/hooks/pre-commit"
fi

# === 5. 安装 L3 GitHub Actions ===
info "安装 L3 PR 即审 Workflow..."

mkdir -p "$PROJECT_ROOT/.github/workflows"
QUINN_YML="$PROJECT_ROOT/.github/workflows/quinn-qa.yml"

if [ -f "$QUINN_YML" ]; then
  info "quinn-qa.yml 已存在，跳过"
else
  cp "$SCRIPT_DIR/.github/workflows/quinn-qa.yml" "$QUINN_YML"
  success "已创建 .github/workflows/quinn-qa.yml"
fi

# === 6. 创建示例测试 ===
info "创建示例测试文件..."

if [ "$PROJECT_TYPE" = "node" ]; then
  mkdir -p "$PROJECT_ROOT/src"
  if [ ! -f "$PROJECT_ROOT/src/smoke.test.ts" ]; then
    cat > "$PROJECT_ROOT/src/smoke.test.ts" << 'TESTEOF'
import { describe, it, expect } from 'vitest'

describe('project setup', () => {
  it('should pass a smoke test', () => {
    expect(true).toBe(true)
  })
})
TESTEOF
    success "已创建 src/smoke.test.ts"
  fi
fi

# === 7. 验证 ===
echo ""
echo "========================================="
echo "  Verifying installation..."
echo "========================================="

PASS=true

echo -n "L1 Hook (settings.local.json): "
if [ -f "$SETTINGS_FILE" ] && grep -q "test-on-change" "$SETTINGS_FILE" 2>/dev/null; then
  echo -e "${GREEN}OK${NC}"
else
  echo -e "${RED}MISSING${NC}"
  PASS=false
fi

echo -n "L2 Hook (pre-commit): "
if [ -x "$PRE_COMMIT" ]; then
  echo -e "${GREEN}OK${NC}"
else
  echo -e "${RED}MISSING${NC}"
  PASS=false
fi

echo -n "L3 Workflow (quinn-qa.yml): "
if [ -f "$QUINN_YML" ]; then
  echo -e "${GREEN}OK${NC}"
else
  echo -e "${RED}MISSING${NC}"
  PASS=false
fi

echo -n "L1 Script (test-on-change.sh): "
if [ -x "$PROJECT_ROOT/.claude/hooks/test-on-change.sh" ]; then
  echo -e "${GREEN}OK${NC}"
else
  echo -e "${RED}MISSING${NC}"
  PASS=false
fi

echo ""

if [ "$PASS" = true ]; then
  echo -e "${GREEN}=========================================${NC}"
  echo -e "${GREEN}  Setup complete!${NC}"
  echo -e "${GREEN}=========================================${NC}"
else
  echo -e "${YELLOW}=========================================${NC}"
  echo -e "${YELLOW}  Setup completed with warnings${NC}"
  echo -e "${YELLOW}=========================================${NC}"
fi

echo ""
echo "下一步："
echo "  1. 在 Claude Code 中开始写代码，L1 会自动运行测试"
echo "  2. git commit 时会自动运行 L2 检查"
echo "  3. 推 PR 到 GitHub 时自动运行 L3（需配置 AI_MODEL 和 AI_API_KEY）"
echo ""
echo "配置 L3 AI 模型（GitHub Settings → Variables）："
echo "  AI_MODEL: claude-sonnet-4-6（默认）或 qwen3-coder-plus 等"
echo "  AI_API_ENDPOINT: API 地址（默认 Anthropic 官方）"
echo "  AI_API_KEY (Secret): 你的 API Key"
echo ""
