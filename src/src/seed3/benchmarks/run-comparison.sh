#!/bin/bash
# run-comparison.sh — Compare Chez, Seed3, and Python3 benchmarks
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SEEDINK="$ROOT/seedink3.scm"

echo "=== Benchmark Comparison: Chez vs Seed3 vs Python3 ==="
echo ""

echo "── N-Queens (N=${SEED_NQUEEN:-14}) ──"
echo ""
echo "  Chez:"
scheme --script "$SCRIPT_DIR/n-queen.chez.scm" 2>&1 | grep -E "solutions|elapsed real"
echo "  Seed3:"
cd "$ROOT" && scheme --script "$SEEDINK" "$SCRIPT_DIR/n-queen.seed" 2>&1 | grep -E "solutions|elapsed real"
echo "  Python3:"
python3 "$SCRIPT_DIR/n-queen.py"
echo ""

echo "── Collatz (limit=${SEED_COLLATZ:-20000000}) ──"
echo ""
echo "  Chez:"
scheme --script "$SCRIPT_DIR/collatz.chez.scm" 2>&1 | grep -E "Collatz|Special|elapsed real"
echo "  Seed3:"
cd "$ROOT" && scheme --script "$SEEDINK" "$SCRIPT_DIR/collatz.seed" 2>&1 | grep -E "Collatz|Special|elapsed real"
echo "  Python3:"
python3 "$SCRIPT_DIR/collatz.py"
echo ""
