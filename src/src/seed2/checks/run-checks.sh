#!/bin/bash
# run-checks.sh — Run seed2 .seed tests and compare against expected output
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SEEDINK="$(cd "$SCRIPT_DIR/../../.." && pwd)/seedink2.scm"

pass=0
fail=0
errors=""

for seed_file in "$SCRIPT_DIR"/*.seed; do
  name="$(basename "$seed_file" .seed)"
  expected="$SCRIPT_DIR/$name.expected"

  if [ ! -f "$expected" ]; then
    echo "  SKIP $name (no .expected file)"
    continue
  fi

  # Capture stdout, strip (time ...) output that run-file emits
  actual=$(scheme --script "$SEEDINK" "$seed_file" 2>/dev/null | sed '/^(time /,$d') || {
    echo "  FAIL $name (runtime error)"
    fail=$((fail + 1))
    errors="$errors\n  $name: runtime error"
    continue
  }

  # Trim trailing whitespace for comparison
  expected_content=$(sed 's/[[:space:]]*$//' "$expected" | sed '/^$/d')
  actual_trimmed=$(echo "$actual" | sed 's/[[:space:]]*$//' | sed '/^$/d')

  if [ "$actual_trimmed" = "$expected_content" ]; then
    echo "  PASS $name"
    pass=$((pass + 1))
  else
    echo "  FAIL $name"
    echo "    expected: $(echo "$expected_content" | head -1)"
    echo "    actual:   $(echo "$actual_trimmed" | head -1)"
    fail=$((fail + 1))
    errors="$errors\n  $name: output mismatch"
  fi
done

echo ""
echo "── seed2 checks: $pass passed, $fail failed ──"
if [ $fail -gt 0 ]; then
  echo -e "Failures:$errors"
  exit 1
fi
