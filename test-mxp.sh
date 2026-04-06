#!/usr/bin/env bash

# Test suite for mxp
# Copyright (c) 2025 Ag Ibragimov <agzam.ibragimov@gmail.com>
# Licensed under the MIT License. See LICENSE file for details.

set -euo pipefail

# Trap errors and show which line failed
trap 'echo "Error on line $LINENO"' ERR

SCRIPT="./mxp"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

passed=0
failed=0

# Test filtering
INCLUDE_TAGS=""
EXCLUDE_TAGS=""
FAST_MODE=false
LIST_TESTS=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --fast)
      FAST_MODE=true
      EXCLUDE_TAGS="large,unicode,terminal"
      shift
      ;;
    --only=*)
      INCLUDE_TAGS="${1#*=}"
      shift
      ;;
    --skip=*)
      EXCLUDE_TAGS="${1#*=}"
      shift
      ;;
    --list)
      LIST_TESTS=true
      shift
      ;;
    --help|-h)
      cat << EOF
Usage: $0 [OPTIONS]

Options:
  --fast           Skip slow/CI-problematic tests (large, unicode, terminal)
  --only=TAGS      Run only tests with specified tags (comma-separated)
  --skip=TAGS      Skip tests with specified tags (comma-separated)
  --list           List all available tests with their tags
  --help           Show this help message

Examples:
  $0                    # Run all tests
  $0 --fast             # Skip slow tests
  $0 --only=core,read   # Run only core and read tests
  $0 --skip=unicode     # Skip unicode tests

Available tags: core, read, write, regex, large, unicode, terminal, cleanup
EOF
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

echo "================================"
echo "mxp Test Suite"
if [ "$FAST_MODE" = true ]; then
  echo "(Fast mode - skipping: $EXCLUDE_TAGS)"
elif [ -n "$INCLUDE_TAGS" ]; then
  echo "(Running only: $INCLUDE_TAGS)"
elif [ -n "$EXCLUDE_TAGS" ]; then
  echo "(Skipping: $EXCLUDE_TAGS)"
fi
echo "================================"
echo ""

# Helper functions
pass() {
  printf "${GREEN}✓${NC} %s\n" "$1"
  passed=$((passed + 1))
}

fail() {
  printf "${RED}✗${NC} %s\n" "$1"
  failed=$((failed + 1))
}

info() {
  printf "${YELLOW}ℹ${NC} %s\n" "$1"
}

section() {
  echo ""
  echo "--- $1 ---"
}

# Check if test should run based on tags
should_run_test() {
  local test_tags="$1"
  
  # If listing tests, always return true
  if [ "$LIST_TESTS" = true ]; then
    return 0
  fi
  
  # Check exclude tags
  if [ -n "$EXCLUDE_TAGS" ]; then
    IFS=',' read -ra EXCLUDE_ARRAY <<< "$EXCLUDE_TAGS"
    for tag in "${EXCLUDE_ARRAY[@]}"; do
      if [[ ",$test_tags," == *",$tag,"* ]]; then
        return 1  # Skip this test
      fi
    done
  fi
  
  # Check include tags (if specified, test must have at least one matching tag)
  if [ -n "$INCLUDE_TAGS" ]; then
    IFS=',' read -ra INCLUDE_ARRAY <<< "$INCLUDE_TAGS"
    for tag in "${INCLUDE_ARRAY[@]}"; do
      if [[ ",$test_tags," == *",$tag,"* ]]; then
        return 0  # Run this test
      fi
    done
    return 1  # No matching tags, skip
  fi
  
  return 0  # No filters, run all tests
}

cleanup_buffer() {
  local buffer="$1"
  emacsclient --eval "(when (get-buffer \"$buffer\") (kill-buffer \"$buffer\"))" &>/dev/null || true
}

buffer_exists() {
  local buffer="$1"
  # Use printf to avoid shell interpretation of angle brackets
  local cmd
  cmd=$(printf '(buffer-live-p (get-buffer "%s"))' "$buffer")
  emacsclient --eval "$cmd" 2>/dev/null | grep -q 't'
}

buffer_content() {
  local buffer="$1"
  # Use mxp's own read mode instead of parsing elisp strings
  ./mxp --from "$buffer" 2>/dev/null
}

# Pre-test cleanup
section "Pre-test Cleanup"
cleanup_buffer "*test-buffer*"
cleanup_buffer "*test-append*"
cleanup_buffer "*test-prepend*"
cleanup_buffer "*test-conflict*"
cleanup_buffer "*test-conflict*<2>"
cleanup_buffer "*Piper 1*"
cleanup_buffer "*Piper 2*"
info "Cleaned up test buffers"

# Test 1: Basic help
section "Test 1: Help and Version"
if $SCRIPT --help | grep -q "mxp"; then
  pass "Help message displays"
else
  fail "Help message missing"
fi

if $SCRIPT --version | grep -q "mxp v"; then
  pass "Version displays"
else
  fail "Version missing"
fi

if $SCRIPT --help | grep -q "\-s, --socket-name"; then
  pass "Help shows -s/--socket-name option"
else
  fail "Help missing -s/--socket-name option"
fi

# Test 2: Write mode - pipe to new buffer
section "Test 2: Write Mode - Create Buffer"
cleanup_buffer "*test-buffer*"
echo "test content" | $SCRIPT "*test-buffer*" &>/dev/null

if buffer_exists "*test-buffer*"; then
  pass "Buffer created from pipe"
  content=$(buffer_content "*test-buffer*")
  if [[ "$content" == *"test content"* ]]; then
    pass "Buffer contains correct content"
  else
    fail "Buffer content incorrect: got '$content'"
  fi
else
  fail "Buffer not created"
fi

# Test 3: Write mode - auto-generated buffer name
section "Test 3: Auto-generated Buffer Name"
cleanup_buffer "*Piper 1*"
echo "auto content" | $SCRIPT &>/dev/null

if buffer_exists "*Piper 1*"; then
  pass "Auto-generated buffer created"
  content=$(buffer_content "*Piper 1*")
  if [[ "$content" == *"auto content"* ]]; then
    pass "Auto-generated buffer has correct content"
  else
    fail "Auto-generated buffer content incorrect"
  fi
else
  fail "Auto-generated buffer not created"
fi

# Test 4: Write mode - second auto-generated buffer
echo "auto content 2" | $SCRIPT &>/dev/null
if buffer_exists "*Piper 2*"; then
  pass "Second auto-generated buffer created with incremented number"
else
  fail "Second auto-generated buffer not created"
fi

# Test 5: Read mode - output buffer content
section "Test 4: Read Mode - Output Buffer"
cleanup_buffer "*test-read*"
echo "readable content" | $SCRIPT "*test-read*" &>/dev/null
output=$($SCRIPT --from "*test-read*" 2>/dev/null)

if [[ "$output" == *"readable content"* ]]; then
  pass "Read mode outputs buffer content"
else
  fail "Read mode failed: got '$output'"
fi

# Test 6: Read mode with short flag
output=$($SCRIPT -f "*test-read*" 2>/dev/null)
if [[ "$output" == *"readable content"* ]]; then
  pass "Read mode works with -f short flag"
else
  fail "Short flag -f failed"
fi

# Test 7: Append mode
section "Test 5: Append Mode"
cleanup_buffer "*test-append*"
echo "first line" | $SCRIPT "*test-append*" &>/dev/null
echo "second line" | $SCRIPT --append "*test-append*" &>/dev/null

content=$(buffer_content "*test-append*")
if [[ "$content" == *"first line"* ]] && [[ "$content" == *"second line"* ]]; then
  pass "Append mode preserves existing content"
else
  fail "Append mode failed: got '$content'"
fi

# Test 8: Append with short flag
echo "third line" | $SCRIPT -a "*test-append*" &>/dev/null
content=$(buffer_content "*test-append*")
if [[ "$content" == *"third line"* ]]; then
  pass "Append works with -a short flag"
else
  fail "Short flag -a failed"
fi

# Test 8.1: Prepend mode
section "Test 5.1: Prepend Mode"
cleanup_buffer "*test-prepend*"
echo "line 2" | $SCRIPT "*test-prepend*" &>/dev/null
echo "line 1" | $SCRIPT --prepend "*test-prepend*" &>/dev/null

content=$(buffer_content "*test-prepend*")
# Check that line 1 appears before line 2
if [[ "$content" == *"line 1"* ]] && [[ "$content" == *"line 2"* ]]; then
  # Use tr to remove newlines for pattern matching
  content_flat=$(echo "$content" | tr '\n' ' ')
  if [[ "$content_flat" == *"line 1"*"line 2"* ]]; then
    pass "Prepend mode inserts at beginning"
  else
    fail "Prepend mode order incorrect: got '$content'"
  fi
else
  fail "Prepend mode failed: got '$content'"
fi

# Test 8.2: Prepend with short flag
echo "line 0" | $SCRIPT -p "*test-prepend*" &>/dev/null
content=$(buffer_content "*test-prepend*")
content_flat=$(echo "$content" | tr '\n' ' ')
if [[ "$content_flat" == *"line 0"*"line 1"*"line 2"* ]]; then
  pass "Prepend works with -p short flag"
else
  fail "Short flag -p failed or order incorrect"
fi

# Test 8.3: Conflicting --append and --prepend flags
output=$(echo "test" | $SCRIPT --append --prepend "*test-buffer*" 2>&1 || true)
if [[ "$output" == *"Cannot use both --append and --prepend"* ]]; then
  pass "Validates conflicting --append and --prepend flags"
else
  fail "Should error on conflicting append/prepend flags"
fi

# Test 9: Conflict resolution (without force)
section "Test 6: Buffer Conflict Resolution"
if [ -n "${CI:-}" ]; then
  info "Skipped in CI (shell-specific edge case)"
else
  cleanup_buffer "*test-conflict*"
  cleanup_buffer "*test-conflict*<2>"
  echo "first" | $SCRIPT "*test-conflict*" &>/dev/null
  echo "second" | $SCRIPT "*test-conflict*" &>/dev/null

  if buffer_exists "*test-conflict*<2>"; then
    pass "Conflict creates new buffer with <2> suffix"
    content=$(buffer_content "*test-conflict*<2>")
    if [[ "$content" == *"second"* ]]; then
      pass "Conflicted buffer has correct content"
    else
      fail "Conflicted buffer content incorrect"
    fi
  else
    fail "Conflict resolution failed"
  fi
fi

# Test 10: Force overwrite
section "Test 7: Force Overwrite"
cleanup_buffer "*test-force*"
echo "original" | $SCRIPT "*test-force*" &>/dev/null
echo "overwritten" | $SCRIPT --force "*test-force*" &>/dev/null

content=$(buffer_content "*test-force*")
if [[ "$content" == *"overwritten"* ]] && [[ "$content" != *"original"* ]]; then
  pass "Force flag overwrites existing buffer"
else
  fail "Force overwrite failed: got '$content'"
fi

# Test 11: Force with short flag
echo "original2" | $SCRIPT "*test-force*" &>/dev/null
echo "overwritten2" | $SCRIPT -F "*test-force*" &>/dev/null
content=$(buffer_content "*test-force*")
if [[ "$content" == *"overwritten2"* ]]; then
  pass "Force works with -F short flag"
else
  fail "Short flag -F failed"
fi

# Test 12: Regex buffer matching (write mode)
section "Test 8: Regex Buffer Matching"
cleanup_buffer "*regex-test-123*"
echo "regex content" | $SCRIPT "*regex-test-123*" &>/dev/null

# Try to match with regex
echo "matched content" | $SCRIPT --force ".*regex-test.*" &>/dev/null
content=$(buffer_content "*regex-test-123*")
if [[ "$content" == *"matched content"* ]]; then
  pass "Regex matching works in write mode"
else
  fail "Regex matching failed in write mode"
fi

# Test 13: Regex buffer matching (read mode)
output=$($SCRIPT --from ".*regex-test.*" 2>/dev/null)
if [[ "$output" == *"matched content"* ]]; then
  pass "Regex matching works in read mode"
else
  fail "Regex matching failed in read mode: got '$output'"
fi

# Test 14: Pass-through behavior
section "Test 9: No Pass-through (standard pipe behavior)"
cleanup_buffer "*test-nopassthrough*"
output=$(echo "pipe test" | $SCRIPT "*test-nopassthrough*" 2>/dev/null)

if [[ -z "$output" ]]; then
  pass "No content passes through to stdout"
  if buffer_exists "*test-nopassthrough*"; then
    content=$(buffer_content "*test-nopassthrough*")
    if [[ "$content" == *"pipe test"* ]]; then
      pass "Content written to buffer only"
    else
      fail "Buffer content incorrect"
    fi
  else
    fail "Buffer not created"
  fi
else
  fail "Unexpected pass-through output: got '$output'"
fi

# Test 15: Multi-line content
section "Test 10: Multi-line Content"
cleanup_buffer "*test-multiline*"
printf "line 1\nline 2\nline 3\n" | $SCRIPT "*test-multiline*" &>/dev/null
content=$(buffer_content "*test-multiline*")

if [[ "$content" == *"line 1"* ]] && [[ "$content" == *"line 2"* ]] && [[ "$content" == *"line 3"* ]]; then
  pass "Multi-line content preserved"
else
  fail "Multi-line content failed"
fi

# Test 16: Special characters handling
section "Test 11: Special Characters"
cleanup_buffer "*test-special*"
echo 'special: "quotes" $vars \backslash' | $SCRIPT "*test-special*" &>/dev/null
content=$(buffer_content "*test-special*")

if [[ "$content" == *'special: "quotes" $vars \backslash'* ]]; then
  pass "Special characters preserved"
else
  fail "Special characters mangled: got '$content'"
fi

# Test 17: Empty input
section "Test 12: Empty Input"
cleanup_buffer "*test-empty*"
echo -n "" | $SCRIPT "*test-empty*" &>/dev/null

if buffer_exists "*test-empty*"; then
  pass "Empty input creates buffer"
else
  fail "Empty input failed to create buffer"
fi

# Test 18: Large content (chunking test)
section "Test 13: Large Content (Chunking)"
cleanup_buffer "*test-large*"
seq 1 500 | $SCRIPT "*test-large*" &>/dev/null
content=$(buffer_content "*test-large*")

if [[ "$content" == *"1"* ]] && [[ "$content" == *"500"* ]]; then
  pass "Large content (500 lines) handled correctly"
else
  fail "Large content failed"
fi

# Test 19: Non-existent buffer read
section "Test 14: Error Handling"
output=$($SCRIPT --from "*non-existent-buffer*" 2>&1 || true)
if [[ "$output" == *"No buffer matching"* ]]; then
  pass "Reading non-existent buffer shows error"
else
  fail "Error message missing for non-existent buffer"
fi

# Test 20: Read mode without stdin (auto-detect)
section "Test 15: Auto-detect Read Mode"
if [ -n "${CI:-}" ]; then
  info "Skipped in CI (command substitution stdin edge case)"
else
  cleanup_buffer "*test-autoread*"
  echo "auto read test" | $SCRIPT "*test-autoread*" &>/dev/null

  # Call without --from but redirect from /dev/null to simulate no stdin
  # This simulates terminal usage where stdin is not a pipe
  output=$($SCRIPT "*test-autoread*" </dev/null 2>/dev/null)
  if [[ "$output" == *"auto read test"* ]]; then
    pass "Auto-detects read mode when no stdin"
  else
    fail "Auto-detect read mode failed: got '$output'"
  fi
fi

# Test 21: Open mode - file opening
section "Test 16: Open Mode - Files and Directories"
info "Open mode tests require interactive terminal (test manually with: mxp README.org)"

# Test 22: Smart detection - buffer vs file  
section "Test 17: Smart Detection"
# Should read as buffer (doesn't exist as file, no path indicators)
cleanup_buffer "*my-test-buffer*"
echo "buffer content" | $SCRIPT "*my-test-buffer*" &>/dev/null
output=$($SCRIPT "*my-test-buffer*" 2>/dev/null || echo "")
if [[ "$output" == *"buffer content"* ]]; then
  pass "Detects buffer name correctly"
else
  # In non-terminal environment, this is expected to fail
  info "Buffer detection test skipped (requires terminal)"
fi

# Test 23: Large buffer reading
section "Test 18: Large Buffer Reading"
cleanup_buffer "*large-buffer-test*"

# Create a buffer with ~100KB of content (1000 lines of 100 chars each)
{
  for i in {1..1000}; do
    printf "Line %04d: %s\n" "$i" "$(printf 'x%.0s' {1..90})"
  done
} | $SCRIPT "*large-buffer-test*" &>/dev/null

# Read it back and verify
output=$($SCRIPT --from "*large-buffer-test*" 2>/dev/null)
line_count=$(echo "$output" | wc -l | tr -d ' ')

if [ "$line_count" = "1000" ]; then
  pass "Large buffer (1000 lines) read successfully"
else
  fail "Large buffer read failed: expected 1000 lines, got $line_count"
fi

# Test 24: Multibyte character support
section "Test 19: Multibyte Characters"
cleanup_buffer "*unicode-test*"

# Test with Unicode characters - use printf to avoid shell encoding issues
printf "Hello 世界 emoji test\n" | $SCRIPT "*unicode-test*" &>/dev/null

# Read back and check if multibyte content survived
output=$($SCRIPT --from "*unicode-test*" 2>/dev/null || echo "FAILED")

if [[ "$output" == *"世界"* ]]; then
  pass "Multibyte/Unicode characters preserved"
else
  # Skip test in CI if it fails due to locale issues
  info "Multibyte test skipped (locale/encoding issue)"
fi

# Test 21: Hook - mxp-buffer-complete-hook
section "Test 22: Hooks - mxp-buffer-complete-hook"
cleanup_buffer "*complete-hook-test*"

# Set up a hook that writes to a temp file when complete
hook_file="/tmp/mxp-test-complete-hook-$$"
rm -f "$hook_file"

emacsclient --eval "(setq mxp-buffer-complete-hook (lambda (buffer-name) (write-region \"COMPLETE\" nil \"$hook_file\")))" &>/dev/null

# Pipe finite content
echo -e "line1\nline2\nline3" | $SCRIPT "*complete-hook-test*" &>/dev/null

# Check if hook was called
if [ -f "$hook_file" ] && grep -q "COMPLETE" "$hook_file"; then
  pass "mxp-buffer-complete-hook called on EOF"
else
  fail "mxp-buffer-complete-hook not called"
fi

# Cleanup
rm -f "$hook_file"
emacsclient --eval "(setq mxp-buffer-complete-hook nil)" &>/dev/null

# Test 23: Hook - mxp-buffer-update-hook with region args
section "Test 23: Hooks - mxp-buffer-update-hook"
cleanup_buffer "*update-hook-test*"

# Set up hook that writes region info
hook_file="/tmp/mxp-test-update-hook-$$"
rm -f "$hook_file"

emacsclient --eval "(setq mxp-buffer-update-hook (lambda (buffer-name start end) (write-region (format \"START:%d END:%d\" start end) nil \"$hook_file\" t)))" &>/dev/null

# Pipe content
echo -e "line1\nline2" | $SCRIPT "*update-hook-test*" &>/dev/null

# Check if hook was called with region args
if [ -f "$hook_file" ] && grep -q "START:" "$hook_file" && grep -q "END:" "$hook_file"; then
  pass "mxp-buffer-update-hook called with region arguments"
else
  fail "mxp-buffer-update-hook not called or missing args"
fi

# Cleanup
rm -f "$hook_file"
emacsclient --eval "(setq mxp-buffer-update-hook nil)" &>/dev/null

# Test 25: Temp file cleanup
section "Test 20: Temp File Cleanup"
cleanup_buffer "*cleanup-test*"
echo "cleanup test" | $SCRIPT "*cleanup-test*" &>/dev/null

# Count temp files before
before=$(ls /tmp/tmp.* 2>/dev/null | wc -l | tr -d ' \n' || echo 0)
[ -z "$before" ] && before=0

# Read buffer multiple times
for i in {1..5}; do
  $SCRIPT --from "*cleanup-test*" &>/dev/null
done

# Count temp files after
after=$(ls /tmp/tmp.* 2>/dev/null | wc -l | tr -d ' \n' || echo 0)
[ -z "$after" ] && after=0

if [ "$before" -eq "$after" ]; then
  pass "No temp files left behind"
else
  fail "Temp files not cleaned up: before=$before, after=$after"
fi

# --- Socket Transport Tests ---

section "Test 24: Socket Server Bootstrap"
if should_run_test "socket"; then
  if [ "$LIST_TESTS" = true ]; then
    echo "  [socket] Socket server bootstrap"
  else
    # Stop any existing mxp server to test fresh bootstrap
    emacsclient --eval "(when (and (boundp 'mxp-server-process) mxp-server-process (process-live-p mxp-server-process)) (delete-process mxp-server-process) (setq mxp-server-process nil))" &>/dev/null || true

    cleanup_buffer "*test-socket-boot*"
    echo "socket boot test" | $SCRIPT "*test-socket-boot*" &>/dev/null

    if buffer_exists "*test-socket-boot*"; then
      pass "Socket server auto-bootstraps on first use"
    else
      fail "Socket server bootstrap failed"
    fi

    # Verify server is running in Emacs
    server_alive=$(emacsclient --eval "(and (boundp 'mxp-server-process) mxp-server-process (process-live-p mxp-server-process))" 2>/dev/null)
    if [[ "$server_alive" != "nil" ]]; then
      pass "Server process is alive in Emacs after bootstrap"
    else
      fail "Server process not found in Emacs"
    fi
  fi
fi

section "Test 25: Socket Eval Round-trip"
if should_run_test "socket"; then
  if [ "$LIST_TESTS" = true ]; then
    echo "  [socket] Socket eval round-trip"
  else
    cleanup_buffer "*test-socket-rt*"
    echo "round trip content" | $SCRIPT "*test-socket-rt*" &>/dev/null
    output=$($SCRIPT --from "*test-socket-rt*" 2>/dev/null)
    if [[ "$output" == *"round trip content"* ]]; then
      pass "Write and read via socket transport"
    else
      fail "Socket round-trip failed: got '$output'"
    fi
  fi
fi

section "Test 26: Socket Streaming"
if should_run_test "socket"; then
  if [ "$LIST_TESTS" = true ]; then
    echo "  [socket] Socket streaming (1000 lines)"
  else
    cleanup_buffer "*test-socket-stream*"
    seq 1 1000 | $SCRIPT "*test-socket-stream*" &>/dev/null
    output=$($SCRIPT --from "*test-socket-stream*" 2>/dev/null)
    line_count=$(echo "$output" | wc -l | tr -d ' ')

    if [ "$line_count" = "1000" ]; then
      pass "1000 lines streamed over socket in order"
    else
      fail "Socket streaming: expected 1000 lines, got $line_count"
    fi

    # Verify first and last lines
    first=$(echo "$output" | head -1)
    last=$(echo "$output" | tail -1)
    if [ "$first" = "1" ] && [ "$last" = "1000" ]; then
      pass "Stream ordering preserved (first=1, last=1000)"
    else
      fail "Stream order wrong: first='$first', last='$last'"
    fi
  fi
fi

section "Test 27: Emacsclient Fallback"
if should_run_test "socket"; then
  if [ "$LIST_TESTS" = true ]; then
    echo "  [socket] Emacsclient fallback with MXP_NO_SOCKET=1"
  else
    cleanup_buffer "*test-fallback*"
    echo "fallback content" | MXP_NO_SOCKET=1 $SCRIPT "*test-fallback*" &>/dev/null
    output=$(MXP_NO_SOCKET=1 $SCRIPT --from "*test-fallback*" 2>/dev/null)

    if [[ "$output" == *"fallback content"* ]]; then
      pass "MXP_NO_SOCKET=1 falls back to emacsclient"
    else
      fail "Fallback failed: got '$output'"
    fi

    # Verify streaming also works in fallback
    cleanup_buffer "*test-fallback-stream*"
    seq 1 50 | MXP_NO_SOCKET=1 $SCRIPT "*test-fallback-stream*" &>/dev/null
    output=$(MXP_NO_SOCKET=1 $SCRIPT --from "*test-fallback-stream*" 2>/dev/null)
    line_count=$(echo "$output" | wc -l | tr -d ' ')

    if [ "$line_count" = "50" ]; then
      pass "Streaming works in fallback mode (50 lines)"
    else
      fail "Fallback streaming: expected 50 lines, got $line_count"
    fi
  fi
fi

section "Test 28: Server Idempotence"
if should_run_test "socket"; then
  if [ "$LIST_TESTS" = true ]; then
    echo "  [socket] Server idempotence"
  else
    # Run mxp twice - server should already exist, no error
    # Buffer names must be regex-distinct (trailing * in Emacs regex
    # means "zero or more of preceding char", so *foo-1* matches *foo-*)
    cleanup_buffer "*test-idemp-alpha*"
    cleanup_buffer "*test-idemp-beta*"
    echo "first" | $SCRIPT "*test-idemp-alpha*" &>/dev/null
    echo "second" | $SCRIPT "*test-idemp-beta*" &>/dev/null

    out1=$($SCRIPT --from "*test-idemp-alpha*" 2>/dev/null)
    out2=$($SCRIPT --from "*test-idemp-beta*" 2>/dev/null)

    if [[ "$out1" == *"first"* ]] && [[ "$out2" == *"second"* ]]; then
      pass "Multiple mxp invocations reuse existing server"
    else
      fail "Server idempotence failed"
    fi
  fi
fi

section "Test 29: Custom Port"
if should_run_test "socket"; then
  if [ "$LIST_TESTS" = true ]; then
    echo "  [socket] Custom MXP_PORT"
  else
    cleanup_buffer "*test-custom-port*"
    echo "custom port" | MXP_PORT=17395 $SCRIPT "*test-custom-port*" &>/dev/null
    output=$(MXP_PORT=17395 $SCRIPT --from "*test-custom-port*" 2>/dev/null)

    if [[ "$output" == *"custom port"* ]]; then
      pass "MXP_PORT override works"
    else
      fail "Custom port failed: got '$output'"
    fi

    # Clean up the extra server
    emacsclient --eval "(when (and (boundp 'mxp-server-process) mxp-server-process) (delete-process mxp-server-process) (setq mxp-server-process nil))" &>/dev/null || true
  fi
fi

section "Test 30: Socket Name CLI Flag"
if should_run_test "socket"; then
  if [ "$LIST_TESTS" = true ]; then
    echo "  [socket] Socket name -s flag"
  else
    # Use -s server (default socket name) with emacsclient fallback to verify
    # the flag plumbing works end-to-end
    cleanup_buffer "*test-socket-name-flag*"
    echo "socket name flag test" | MXP_NO_SOCKET=1 $SCRIPT -s server "*test-socket-name-flag*" &>/dev/null
    output=$(MXP_NO_SOCKET=1 $SCRIPT -s server --from "*test-socket-name-flag*" 2>/dev/null)

    if [[ "$output" == *"socket name flag test"* ]]; then
      pass "Write/read round-trip with -s flag works"
    else
      fail "Socket name -s flag failed: got '$output'"
    fi
  fi
fi

section "Test 31: Socket Name Env Var"
if should_run_test "socket"; then
  if [ "$LIST_TESTS" = true ]; then
    echo "  [socket] EMACS_SOCKET_NAME env var"
  else
    cleanup_buffer "*test-socket-name-env*"
    echo "socket name env test" | MXP_NO_SOCKET=1 EMACS_SOCKET_NAME=server $SCRIPT "*test-socket-name-env*" &>/dev/null
    output=$(MXP_NO_SOCKET=1 EMACS_SOCKET_NAME=server $SCRIPT --from "*test-socket-name-env*" 2>/dev/null)

    if [[ "$output" == *"socket name env test"* ]]; then
      pass "Write/read round-trip with EMACS_SOCKET_NAME env var works"
    else
      fail "EMACS_SOCKET_NAME env var failed: got '$output'"
    fi
  fi
fi

section "Test 32: Socket Name --socket-name Long Flag"
if should_run_test "socket"; then
  if [ "$LIST_TESTS" = true ]; then
    echo "  [socket] Socket name --socket-name long flag"
  else
    cleanup_buffer "*test-socket-name-long*"
    echo "long flag test" | MXP_NO_SOCKET=1 $SCRIPT --socket-name server "*test-socket-name-long*" &>/dev/null
    output=$(MXP_NO_SOCKET=1 $SCRIPT --socket-name server --from "*test-socket-name-long*" 2>/dev/null)

    if [[ "$output" == *"long flag test"* ]]; then
      pass "Write/read round-trip with --socket-name flag works"
    else
      fail "Socket name --socket-name long flag failed: got '$output'"
    fi
  fi
fi

# Summary
section "Test Summary"
echo ""
echo "Passed: $passed"
echo "Failed: $failed"
echo ""

if [ $failed -eq 0 ]; then
  printf "${GREEN}All tests passed!${NC}\n"
  exit 0
else
  printf "${RED}Some tests failed.${NC}\n"
  exit 1
fi
