#!/bin/bash
# test-on-change.sh — L1: 编辑即测
# 触发: PostToolUse Edit|Write（异步）
# 输入: stdin JSON
# 来源: https://github.com/{user}/three-layer-test

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[ -z "$FILE_PATH" ] && exit 0
[ ! -f "$FILE_PATH" ] && exit 0

# === 智能排除 ===
case "$FILE_PATH" in
  */memory/*|*/archive/*|*/hooks/*|*/node_modules/*) exit 0 ;;
esac

BASENAME=$(basename "$FILE_PATH")
case "$BASENAME" in
  *.json|*.yaml|*.yml|*.toml|*.config.*|*.conf) exit 0 ;;
esac

EXT="${FILE_PATH##*.}"
DIR=$(dirname "$FILE_PATH")

# === 仅对源代码文件触发 ===
case "$EXT" in
  ts|tsx|js|jsx|py|go|rs) ;;
  *) exit 0 ;;
esac

# === 排除测试文件本身 ===
case "$BASENAME" in
  *.test.*|*.spec.*|*.test_*|test_*|*_test.*) exit 0 ;;
esac

# === 防抖：30秒内不重复测试 ===
DEBOUNCE_FILE="/tmp/.claude-hook-test-debounce"
NOW=$(date +%s)
if [ -f "$DEBOUNCE_FILE" ]; then
  LAST_RUN=$(cat "$DEBOUNCE_FILE" 2>/dev/null || echo 0)
  if [ $((NOW - LAST_RUN)) -lt 30 ]; then
    exit 0
  fi
fi
echo "$NOW" > "$DEBOUNCE_FILE"

# === 查找项目根目录 ===
PROJECT_ROOT="$DIR"
while [ "$PROJECT_ROOT" != "/" ]; do
  if [ -f "$PROJECT_ROOT/package.json" ] || [ -f "$PROJECT_ROOT/pyproject.toml" ] || [ -f "$PROJECT_ROOT/go.mod" ]; then
    break
  fi
  PROJECT_ROOT=$(dirname "$PROJECT_ROOT")
done

[ "$PROJECT_ROOT" = "/" ] && exit 0

# === 根据项目类型运行测试 ===
LOG_FILE="$PROJECT_ROOT/.three-layer-test.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

if [ -f "$PROJECT_ROOT/package.json" ]; then
  if grep -q '"vitest"' "$PROJECT_ROOT/package.json" 2>/dev/null; then
    echo "[$TIMESTAMP] Running vitest for $FILE_PATH" >> "$LOG_FILE"
    cd "$PROJECT_ROOT"
    BASENAME_NOEXT="${FILE_PATH##*/}"
    BASENAME_NOEXT="${BASENAME_NOEXT%.*}"
    npx --no vitest run --reporter=verbose "$BASENAME_NOEXT" >> "$LOG_FILE" 2>&1 || true
  elif grep -q '"jest"' "$PROJECT_ROOT/package.json" 2>/dev/null; then
    echo "[$TIMESTAMP] Running jest for $FILE_PATH" >> "$LOG_FILE"
    cd "$PROJECT_ROOT"
    BASENAME_NOEXT="${FILE_PATH##*/}"
    BASENAME_NOEXT="${BASENAME_NOEXT%.*}"
    npx --no jest --testPathPattern="$BASENAME_NOEXT" >> "$LOG_FILE" 2>&1 || true
  fi
elif [ -f "$PROJECT_ROOT/pyproject.toml" ]; then
  if command -v pytest &>/dev/null; then
    echo "[$TIMESTAMP] Running pytest for $FILE_PATH" >> "$LOG_FILE"
    cd "$PROJECT_ROOT"
    BASENAME_NOEXT="${FILE_PATH##*/}"
    BASENAME_NOEXT="${BASENAME_NOEXT%.*}"
    pytest -x -q "tests/" -k "$BASENAME_NOEXT" >> "$LOG_FILE" 2>&1 || true
  fi
fi

exit 0
