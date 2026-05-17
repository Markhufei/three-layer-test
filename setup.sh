#!/bin/bash
# setup.sh — 一键安装三层自动测试 v2
# 用法: bash setup.sh 或 bash <(curl -fsSL .../setup.sh)

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
echo "  Three-Layer Auto-Test v2"
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
    error "需要 git 仓库才能安装 L2"
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
  warn "未检测到已知项目类型"
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

# === 2. 创建测试配置 ===
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

# === 3. 安装 L1 编辑即测 ===
info "安装 L1 编辑即测 Hook..."

mkdir -p "$PROJECT_ROOT/.claude/hooks"

if [ -f "$SCRIPT_DIR/hooks/test-on-change.sh" ]; then
  cp "$SCRIPT_DIR/hooks/test-on-change.sh" "$PROJECT_ROOT/.claude/hooks/test-on-change.sh"
else
  cat > "$PROJECT_ROOT/.claude/hooks/test-on-change.sh" << 'HOOK_EOF'
#!/bin/bash
# test-on-change.sh — L1: 编辑即测
# 来源: https://github.com/Markhufei/three-layer-test
set -euo pipefail
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE_PATH" ] && exit 0
[ ! -f "$FILE_PATH" ] && exit 0
case "$FILE_PATH" in */memory/*|*/archive/*|*/hooks/*|*/node_modules/*) exit 0 ;; esac
BASENAME=$(basename "$FILE_PATH")
case "$BASENAME" in *.json|*.yaml|*.yml|*.toml|*.config.*|*.conf) exit 0 ;; esac
EXT="${FILE_PATH##*.}"
case "$EXT" in ts|tsx|js|jsx|py|go|rs) ;; *) exit 0 ;; esac
case "$BASENAME" in *.test.*|*.spec.*|*.test_*|test_*|*_test.*) exit 0 ;; esac
DEBOUNCE_FILE="/tmp/.claude-hook-test-debounce"
NOW=$(date +%s)
if [ -f "$DEBOUNCE_FILE" ]; then
  LAST_RUN=$(cat "$DEBOUNCE_FILE" 2>/dev/null || echo 0)
  [ $((NOW - LAST_RUN)) -lt 30 ] && exit 0
fi
echo "$NOW" > "$DEBOUNCE_FILE"
PROJECT_ROOT="$FILE_PATH"
DIR=$(dirname "$FILE_PATH")
while [ "$PROJECT_ROOT" != "/" ]; do
  [ -f "$PROJECT_ROOT/package.json" ] || [ -f "$PROJECT_ROOT/pyproject.toml" ] || [ -f "$PROJECT_ROOT/go.mod" ] && break
  PROJECT_ROOT=$(dirname "$PROJECT_ROOT")
done
[ "$PROJECT_ROOT" = "/" ] && exit 0
LOG_FILE="$PROJECT_ROOT/.three-layer-test.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
if [ -f "$PROJECT_ROOT/package.json" ]; then
  if grep -q '"vitest"' "$PROJECT_ROOT/package.json" 2>/dev/null; then
    echo "[$TIMESTAMP] Running vitest for $FILE_PATH" >> "$LOG_FILE"
    cd "$PROJECT_ROOT"
    BN="${FILE_PATH##*/}"; BN="${BN%.*}"
    npx --no vitest run --reporter=verbose "$BN" >> "$LOG_FILE" 2>&1 || true
  elif grep -q '"jest"' "$PROJECT_ROOT/package.json" 2>/dev/null; then
    echo "[$TIMESTAMP] Running jest for $FILE_PATH" >> "$LOG_FILE"
    cd "$PROJECT_ROOT"
    BN="${FILE_PATH##*/}"; BN="${BN%.*}"
    npx --no jest --testPathPattern="$BN" >> "$LOG_FILE" 2>&1 || true
  fi
elif [ -f "$PROJECT_ROOT/pyproject.toml" ]; then
  if command -v pytest &>/dev/null; then
    echo "[$TIMESTAMP] Running pytest for $FILE_PATH" >> "$LOG_FILE"
    cd "$PROJECT_ROOT"
    BN="${FILE_PATH##*/}"; BN="${BN%.*}"
    pytest -x -q "tests/" -k "$BN" >> "$LOG_FILE" 2>&1 || true
  fi
fi
exit 0
HOOK_EOF
fi
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
      { "matcher": "Write", "hooks": [$HOOK_ENTRY] },
      { "matcher": "Edit", "hooks": [$HOOK_ENTRY] }
    ]
  }
}
SEOF
  success "已创建 .claude/settings.local.json"
else
  if grep -q "test-on-change" "$SETTINGS_FILE" 2>/dev/null; then
    info "L1 Hook 已存在，跳过"
  else
    info "追加 L1 Hook 到现有配置..."
    python3 -c "
import json
with open('$SETTINGS_FILE', 'r') as f: config = json.load(f)
if 'hooks' not in config: config['hooks'] = {}
entry = {'type':'command','command':'.claude/hooks/test-on-change.sh','timeout':30,'statusMessage':'Running tests...','async':True}
if 'PostToolUse' not in config['hooks']:
    config['hooks']['PostToolUse'] = [{'matcher':'Write','hooks':[entry]},{'matcher':'Edit','hooks':[entry]}]
else:
    for rule in config['hooks']['PostToolUse']:
        if rule.get('matcher') in ('Write','Edit','*'):
            if not any('test-on-change' in h.get('command','') for h in rule.get('hooks',[])):
                rule['hooks'].append(entry)
with open('$SETTINGS_FILE', 'w') as f: json.dump(config, f, indent=2, ensure_ascii=False)
print('Hook appended')
"
    success "L1 Hook 已追加"
  fi
fi

# === 4. 安装 L2 提交即检（声明式配置）===
info "安装 L2 提交即检 Hook..."

PRE_COMMIT_CFG="$PROJECT_ROOT/.pre-commit-config.yaml"

if [ ! -f "$PRE_COMMIT_CFG" ]; then
  if [ -f "$SCRIPT_DIR/templates/.pre-commit-config.yaml" ]; then
    cp "$SCRIPT_DIR/templates/.pre-commit-config.yaml" "$PRE_COMMIT_CFG"
    success "已创建 .pre-commit-config.yaml"
  else
    # 内嵌默认配置
    cat > "$PRE_COMMIT_CFG" << 'CFGEOF'
# pre-commit-config.yaml — 声明式提交前检查
# 按需启用/禁用 hook，修改此文件即可
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: check-added-large-files
        args: ['--maxkb=5000']
      - id: detect-private-key
      - id: check-merge-conflict
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-json

  - repo: local
    hooks:
      - id: typecheck
        name: TypeScript type check
        entry: npx tsc --noEmit
        language: system
        pass_filenames: false
        types: [ts, tsx]
      - id: lint
        name: ESLint code style
        entry: npx eslint
        language: system
        types: [ts, tsx]
      - id: test
        name: vitest unit tests
        entry: npx vitest run
        language: system
        pass_filenames: false
        types: [ts, tsx]
      - id: debug-scan
        name: debug code scan
        entry: bash -c 'FOUND=false; for f in "$@"; do if grep -n "console\.log\|debugger" "$f" 2>/dev/null; then FOUND=true; fi; done; if $FOUND; then echo "ERROR: debug code found"; exit 1; fi'
        language: system
        types: [ts, tsx]
CFGEOF
    success "已创建 .pre-commit-config.yaml（内嵌模板）"
  fi
else
  info ".pre-commit-config.yaml 已存在，跳过"
fi

# 同时创建兼容的 pre-commit bash hook（用于未安装 pre-commit 框架的情况）
PRE_COMMIT="$PROJECT_ROOT/.git/hooks/pre-commit"
if [ ! -f "$PRE_COMMIT" ]; then
  cat > "$PRE_COMMIT" << 'PCEOF'
#!/bin/bash
# pre-commit — L2: 提交前检查
# 如果存在 .pre-commit-config.yaml 且有 pre-commit 命令，优先使用声明式框架
# 否则回退到 bash hook

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

if [ -f .pre-commit-config.yaml ] && command -v pre-commit &>/dev/null; then
  pre-commit run --config .pre-commit-config.yaml
  exit $?
fi

# 回退：直接运行检查（仅检查变更文件）
CHANGED=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.(ts|tsx)$' || true)
[ -z "$CHANGED" ] && exit 0

echo "Running pre-commit checks..."

echo "→ tsc --noEmit"
npx tsc --noEmit || { echo "ERROR: Type check failed"; exit 1; }

echo "→ eslint"
echo "$CHANGED" | xargs npx eslint --no-error-on-unmatched-pattern 2>/dev/null || true

echo "→ vitest"
npx vitest run || { echo "ERROR: Tests failed"; exit 1; }

echo "→ Scanning for debug code..."
FOUND=false
for f in $CHANGED; do
  if grep -n "console\.log\|debugger" "$f" 2>/dev/null; then FOUND=true; fi
done
if $FOUND; then
  echo "ERROR: debug code found in staged files"
  exit 1
fi

echo "All checks passed!"
PCEOF
  chmod +x "$PRE_COMMIT"
  success "已创建 .git/hooks/pre-commit（bash 回退模式）"
else
  info "pre-commit hook 已存在，跳过"
fi

# === 5. 安装 L3 PR 即审 ===
info "安装 L3 PR 即审 Workflow..."

mkdir -p "$PROJECT_ROOT/.github/workflows"
QUINN_YML="$PROJECT_ROOT/.github/workflows/quinn-qa.yml"

if [ -f "$QUINN_YML" ]; then
  info "quinn-qa.yml 已存在，跳过"
elif [ -f "$SCRIPT_DIR/.github/workflows/quinn-qa.yml" ]; then
  cp "$SCRIPT_DIR/.github/workflows/quinn-qa.yml" "$QUINN_YML"
  success "已创建 .github/workflows/quinn-qa.yml"
else
  warn "无法获取 quinn-qa.yml，请从 https://github.com/Markhufei/three-layer-test 手动下载"
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

echo -n "L2 Config (.pre-commit-config.yaml): "
if [ -f "$PRE_COMMIT_CFG" ]; then
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
echo "升级亮点："
echo "  L2 — 声明式 .pre-commit-config.yaml，按需启用/禁用 hook"
echo "  L3 — 3 个 AI Agent 并行分析（Security + Bug + Style）"
echo "       + 行级评论直接贴到代码 diff 上"
echo ""
echo "下一步："
echo "  1. 写代码 → L1 自动测试"
echo "  2. git commit → L2 自动检查"
echo "  3. 推 PR → L3 多 Agent 分析 + 行级评论"
echo ""
echo "L3 AI 模型配置（GitHub Settings → Variables）："
echo "  AI_MODEL: qwen3.6-plus（默认）/ claude-sonnet-4-6 等"
echo "  AI_API_ENDPOINT: API 地址（默认 Anthropic）"
echo "  AI_API_KEY (Secret): 你的 API Key"
echo ""
