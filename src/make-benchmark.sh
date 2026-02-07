#!/bin/bash
# make-benchmark.sh -- Configurable benchmark: seed.scm (vau) vs Chez Scheme
#
# Usage: bash make-benchmark.sh [OPTIONS]
#
# Options:
#   --nq-n=N               N-Queens board size            (default: 14)
#   --collatz=N            Collatz search limit            (default: 20000000)
#   --special=N            Count-special limit              (default: 40000000)
#   --iters=N              Repetitions per benchmark        (default: 1)
#   --abacus-expr-depth=N  Abacus balanced-tree depth       (default: 27)
#   --only=BENCH           Run only: nqueens, collatz, abacus, or all (default: all)
#
# All timings use monotonic clocks inside Chez Scheme to eliminate
# process startup noise.  Seed compile vs execute are reported separately.

set -euo pipefail

# ── defaults ──────────────────────────────────────────────────────────
NQ_N=14
COLLATZ_LIMIT=20000000
SPECIAL_LIMIT=40000000
ABACUS_EXPR_DEPTH=27
ITERS=1
ONLY=all

for arg in "$@"; do
  case "$arg" in
    --nq-n=*)              NQ_N="${arg#*=}" ;;
    --collatz=*)           COLLATZ_LIMIT="${arg#*=}" ;;
    --special=*)           SPECIAL_LIMIT="${arg#*=}" ;;
    --abacus-expr-depth=*) ABACUS_EXPR_DEPTH="${arg#*=}" ;;
    --iters=*)             ITERS="${arg#*=}" ;;
    --only=*)              ONLY="${arg#*=}" ;;
    -h|--help)
      sed -n '2,/^$/s/^# //p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ── helper: run one benchmark, collect monotonic time ─────────────────
#  run_bench <label> <runner> <file> <iters>
#  runner = "seed" | "chez"
#  Prints: <label> <best_time> <all_times...>
#  For seed, also prints compile time.
run_bench() {
  local label="$1" runner="$2" file="$3" iters="$4"
  local best="" compile_best="" times="" compile_times=""

  for (( i=1; i<=iters; i++ )); do
    local stderr_file="$TMP/stderr.$i"
    if [ "$runner" = "seed" ]; then
      scheme --script seed.scm "$file" >/dev/null 2>"$stderr_file"
      # Parse seed.scm timing line:
      #   Timing: compile=0.000s (0.0%), execute=17.571s (100.0%), total=17.571s
      local ct et
      ct=$(sed -n 's/.*compile=\([0-9.]*\)s.*/\1/p' "$stderr_file")
      et=$(sed -n 's/.*execute=\([0-9.]*\)s.*/\1/p' "$stderr_file")
      times="$times $et"
      compile_times="$compile_times $ct"
      if [ -z "$best" ] || awk "BEGIN{exit !($et < $best)}"; then
        best="$et"
        compile_best="$ct"
      fi
    else
      scheme --script "$file" >/dev/null 2>"$stderr_file"
      # Parse MONOTONIC: <seconds>
      local mt
      mt=$(sed -n 's/.*MONOTONIC: \([0-9.]*\)s.*/\1/p' "$stderr_file")
      times="$times $mt"
      if [ -z "$best" ] || awk "BEGIN{exit !($mt < $best)}"; then
        best="$mt"
      fi
    fi
  done

  # Output structured result
  local display_label="${label#*|}"
  if [ "$runner" = "seed" ]; then
    printf "  %-33s  compile: %8ss  execute: %8ss" "$display_label" "$compile_best" "$best"
    if [ "$iters" -gt 1 ]; then
      printf "  (best of %d)" "$iters"
    fi
    printf "\n"
  else
    local fmt_best
    fmt_best=$(awk "BEGIN{printf \"%.3f\", $best}")
    printf "  %-33s                     execute: %8ss" "$display_label" "$fmt_best"
    if [ "$iters" -gt 1 ]; then
      printf "  (best of %d)" "$iters"
    fi
    printf "\n"
  fi

  # Stash for summary table (TAB-separated)
  printf "%s\t%s\t%s\t%s\n" "$label" "$runner" "${compile_best:-n/a}" "$best" >> "$TMP/results.csv"
}

# ══════════════════════════════════════════════════════════════════════
#  Prepare benchmark source files (sed parameter substitution)
# ══════════════════════════════════════════════════════════════════════

sed "s/(n-queens 14)/(n-queens $NQ_N)/g" \
  benchmark-n-queen.seed > "$TMP/nq-seed.k"

sed "s/(n-queens 14)/(n-queens $NQ_N)/g" \
  benchmark-n-queen.scm > "$TMP/nq-chez.scm"

sed -e "s/find-longest-collatz 20000000/find-longest-collatz $COLLATZ_LIMIT/" \
    -e "s/count-special 40000000/count-special $SPECIAL_LIMIT/" \
  benchmark-collatz.seed > "$TMP/mb-seed.k"

sed -e "s/find-longest-collatz 20000000/find-longest-collatz $COLLATZ_LIMIT/" \
    -e "s/count-special 40000000/count-special $SPECIAL_LIMIT/" \
  benchmark-collatz.scm > "$TMP/mb-chez.scm"

sed "s/make-balanced-tree 27/make-balanced-tree $ABACUS_EXPR_DEPTH/g" \
  benchmark-abacus.seed > "$TMP/ab-seed.k"

sed "s/make-balanced-tree 27/make-balanced-tree $ABACUS_EXPR_DEPTH/g" \
  benchmark-abacus.scm > "$TMP/ab-chez.scm"

# ══════════════════════════════════════════════════════════════════════
#  Run
# ══════════════════════════════════════════════════════════════════════

> "$TMP/results.csv"   # reset

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  seed.scm benchmark   (iters=$ITERS)                               ║"
echo "╠══════════════════════════════════════════════════════════════════════╣"
printf "║  N-Queens n=%-5s  Collatz ≤ %-12s  Special ≤ %-12s  ║\n" \
       "$NQ_N" "$COLLATZ_LIMIT" "$SPECIAL_LIMIT"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo

if [ "$ONLY" = "all" ] || [ "$ONLY" = "nqueens" ]; then
  echo "── N-Queens (n=$NQ_N) ─────────────────────────────────────────────"
  run_bench "N-Queens|seed.scm (vau)" seed "$TMP/nq-seed.k"    "$ITERS"
  run_bench "N-Queens|Chez (native)"  chez "$TMP/nq-chez.scm"  "$ITERS"
  echo
fi

if [ "$ONLY" = "all" ] || [ "$ONLY" = "collatz" ]; then
  echo "── Collatz: vau vs syntax-rules ─────────────────────────────────"
  run_bench "Collatz|seed.scm (vau)"       seed "$TMP/mb-seed.k"    "$ITERS"
  run_bench "Collatz|Chez (syntax-rules)"  chez "$TMP/mb-chez.scm"  "$ITERS"
  echo
fi

if [ "$ONLY" = "all" ] || [ "$ONLY" = "abacus" ]; then
  echo "── Abacus: match catamorphism (depth=$ABACUS_EXPR_DEPTH) ──────────"

  # Seed — parse compile/execute from stderr, tree/eval sub-timings from stdout
  seed_best="" seed_compile="" seed_tree="" seed_eval=""
  for (( i=1; i<=ITERS; i++ )); do
    scheme --script seed.scm "$TMP/ab-seed.k" >"$TMP/ab-out.$i" 2>"$TMP/ab-err.$i"
    ct=$(sed -n 's/.*compile=\([0-9.]*\)s.*/\1/p' "$TMP/ab-err.$i")
    et=$(sed -n 's/.*execute=\([0-9.]*\)s.*/\1/p' "$TMP/ab-err.$i")
    tree_ns=$(sed -n 's/^TREE-BUILD-NS: \([0-9]*\)/\1/p' "$TMP/ab-out.$i")
    eval_ns=$(sed -n 's/^EVAL-EXPR-NS: \([0-9]*\)/\1/p' "$TMP/ab-out.$i")
    if [ -z "$seed_best" ] || awk "BEGIN{exit !($et < $seed_best)}"; then
      seed_best="$et"; seed_compile="$ct"
      seed_tree=$(awk "BEGIN{printf \"%.3f\", $tree_ns / 1000000000}")
      seed_eval=$(awk "BEGIN{printf \"%.3f\", $eval_ns / 1000000000}")
    fi
  done
  printf "  %-33s  compile: %8ss  tree: %8ss  eval: %8ss" \
         "seed.scm (vau match)" "$seed_compile" "$seed_tree" "$seed_eval"
  [ "$ITERS" -gt 1 ] && printf "  (best of %d)" "$ITERS"
  printf "\n"

  # Chez — parse tree/eval sub-timings + MONOTONIC from stderr
  chez_best="" chez_tree="" chez_eval=""
  for (( i=1; i<=ITERS; i++ )); do
    scheme --script "$TMP/ab-chez.scm" >/dev/null 2>"$TMP/ab-err.$i"
    mt=$(sed -n 's/.*MONOTONIC: \([0-9.]*\)s.*/\1/p' "$TMP/ab-err.$i")
    tree_s=$(sed -n 's/.*TREE-BUILD: \([0-9.]*\)s.*/\1/p' "$TMP/ab-err.$i")
    eval_s=$(sed -n 's/.*EVAL-EXPR: \([0-9.]*\)s.*/\1/p' "$TMP/ab-err.$i")
    if [ -z "$chez_best" ] || awk "BEGIN{exit !($mt < $chez_best)}"; then
      chez_best="$mt"; chez_tree="$tree_s"; chez_eval="$eval_s"
    fi
  done
  chez_tree_fmt=$(awk "BEGIN{printf \"%.3f\", $chez_tree}")
  chez_eval_fmt=$(awk "BEGIN{printf \"%.3f\", $chez_eval}")
  printf "  %-33s                      tree: %8ss  eval: %8ss" \
         "Chez (SRFI-241 match)" "$chez_tree_fmt" "$chez_eval_fmt"
  [ "$ITERS" -gt 1 ] && printf "  (best of %d)" "$ITERS"
  printf "\n"

  # Stash for summary table
  printf "%s\t%s\t%s\t%s\n" "Abacus|seed.scm (vau match)" "seed" "$seed_compile" "$seed_best" >> "$TMP/results.csv"
  printf "%s\t%s\t%s\t%s\n" "Abacus|Chez (SRFI-241 match)" "chez" "n/a" "$chez_best" >> "$TMP/results.csv"
  echo
fi

# ══════════════════════════════════════════════════════════════════════
#  Summary table
# ══════════════════════════════════════════════════════════════════════

echo "── Summary ────────────────────────────────────────────────────────"
printf "%-20s  %10s  %10s  %10s  %7s\n" \
       "Benchmark" "Compile" "Seed (vau)" "Chez" "Ratio"
printf "%-20s  %10s  %10s  %10s  %7s\n" \
       "────────────────────" "──────────" "──────────" "──────────" "───────"

prev_seed="" prev_compile="" prev_bench=""
while IFS=$'\t' read -r label runner ct et; do
  bench="${label%%|*}"
  if [ "$runner" = "seed" ]; then
    prev_seed="$et"
    prev_compile="$ct"
    prev_bench="$bench"
  else
    ratio=$(awk -v s="$prev_seed" -v c="$et" 'BEGIN{printf "%.2fx", s / c}')
    cs=$(awk -v v="$prev_compile" 'BEGIN{printf "%.3f", v}')
    ss=$(awk -v v="$prev_seed" 'BEGIN{printf "%.3f", v}')
    cs_chez=$(awk -v v="$et" 'BEGIN{printf "%.3f", v}')
    printf "%-20s  %9ss  %9ss  %9ss  %7s\n" \
           "$prev_bench" "$cs" "$ss" "$cs_chez" "$ratio"
  fi
done < "$TMP/results.csv"
