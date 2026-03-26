#!/bin/bash
# make-benchmark.sh -- Configurable benchmark: seed.scm (vau) vs Chez Scheme
#
# Usage: bash make-benchmark.sh [OPTIONS]
#
# Options:
#   --nq-n=N               N-Queens board size            (default: 14)
#   --collatz=N            Collatz search limit            (default: 20000000)
#   --special=N            Count-special limit              (default: 40000000)
#   --abacus-expr-depth=N  Abacus balanced-tree depth       (default: 27)
#   --abacus2-expr-depth=N Abacus2 balanced-tree depth      (default: 17)
#   --gremlin-n=N          Gremlin graph vertices            (default: 20000)
#   --gremlin-e=N          Gremlin edges per vertex          (default: 20)
#   --iters=N              Repetitions per benchmark        (default: 1)
#   --only=BENCH           Run only: nqueens, collatz, abacus, abacus2, gremlin, or all (default: all)
#   --drivers=LIST         Drivers to run: all, seedink, seedink2, scheme, binink, binink-aot,
#                          or comma-separated (default: all)
#   --dev                  Enable dev mode (optimize-level 0, GC, profiling)
#   --verbose              Show compilation messages (default: quiet)
#
# All timings use Chez Scheme's (time ...) form, which outputs to stderr.
# make-benchmark.sh extracts "elapsed real time" values from time output.

set -euo pipefail

# ── defaults ──────────────────────────────────────────────────────────
NQ_N=14
COLLATZ_LIMIT=20000000
SPECIAL_LIMIT=40000000
ABACUS_EXPR_DEPTH=27
ABACUS2_EXPR_DEPTH=17
GREMLIN_N=20000
GREMLIN_E=20
ITERS=1
ONLY=all
DRIVERS="all"
DEV=false
QUIET=true

for arg in "$@"; do
  case "$arg" in
    --nq-n=*)              NQ_N="${arg#*=}" ;;
    --collatz=*)           COLLATZ_LIMIT="${arg#*=}" ;;
    --special=*)           SPECIAL_LIMIT="${arg#*=}" ;;
    --abacus-expr-depth=*) ABACUS_EXPR_DEPTH="${arg#*=}" ;;
    --abacus2-expr-depth=*) ABACUS2_EXPR_DEPTH="${arg#*=}" ;;
    --gremlin-n=*)         GREMLIN_N="${arg#*=}" ;;
    --gremlin-e=*)         GREMLIN_E="${arg#*=}" ;;
    --iters=*)             ITERS="${arg#*=}" ;;
    --only=*)              ONLY="${arg#*=}" ;;
    --drivers=*)           DRIVERS="${arg#*=}" ;;
    --dev)                 DEV=true ;;
    --verbose)             QUIET=false ;;
    -h|--help)
      sed -n '2,/^$/s/^# //p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

# Build scheme command options based on DEV flag
if [ "$DEV" = true ]; then
  SCHEME_OPTS="--optimize-level 0"
  export SEED_DEV=1
else
  SCHEME_OPTS="--optimize-level 2"
fi

# Build binink command options based on DEV flag
if [ "$DEV" = true ]; then
  BININK_OPTS="--dev --optimize-level=0"
else
  BININK_OPTS="--disable-garbage-collector --optimize-level=2"
fi

# Parse --drivers option
if [ "$DRIVERS" = "all" ]; then
  # Default drivers: seedink (Seed1), seedink2 (Seed2), and scheme (native Chez)
  SELECTED_DRIVERS=(seedink seedink2 scheme)
else
  IFS=',' read -ra SELECTED_DRIVERS <<< "$DRIVERS"
fi

# Validate selected drivers
for driver in "${SELECTED_DRIVERS[@]}"; do
  if [[ "$driver" != "seedink" && "$driver" != "seedink2" && "$driver" != "scheme" && \
        "$driver" != "binink" && "$driver" != "binink-aot" ]]; then
    echo "Error: Unknown driver '$driver'" >&2
    echo "Supported drivers: seedink, seedink2, scheme, binink, binink-aot" >&2
    exit 1
  fi
done

# Check binink availability
for driver in "${SELECTED_DRIVERS[@]}"; do
  if [[ "$driver" == "binink"* ]] && ! command -v binink &> /dev/null; then
    echo "Error: binink driver selected but 'binink' command not found" >&2
    echo "Please install binink or remove binink drivers from selection" >&2
    exit 1
  fi
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ── helper: run one benchmark, collect monotonic time ─────────────────
#  run_bench <label> <runner> <file> <iters>
#  runner = "seedink" | "scheme"
#  Prints: <label> <best_time> <all_times...>
#  For seedink, also prints compile time.
run_bench() {
  local label="$1" driver="$2" file="$3" iters="$4"
  local best="" compile_best="" wall_best="" times="" compile_times=""

  for (( i=1; i<=iters; i++ )); do
    local stderr_file="$TMP/stderr.$i"
    if [ "$driver" = "seedink" ] || [ "$driver" = "seedink2" ]; then
      local wall_start wall_end wall_secs stdout_file script
      if [ "$driver" = "seedink2" ]; then script="seedink2.scm"; else script="seedink.scm"; fi
      stdout_file="$TMP/stdout.$i"
      wall_start=$(date +%s%N)
      scheme --script "$script" "$file" >"$stdout_file" 2>&1
      wall_end=$(date +%s%N)
      wall_secs=$(awk "BEGIN{printf \"%.3f\", ($wall_end - $wall_start) / 1000000000}")
      # Parse Chez time output (elapsed real time) from stdout
      local et
      et=$(sed -n 's/^[[:space:]]*\([0-9.]*\)s elapsed real time.*/\1/p' "$stdout_file" | tail -1)
      times="$times $et"
      compile_times="$compile_times n/a"
      if [ -z "$best" ] || awk "BEGIN{exit !($et < $best)}"; then
        best="$et"
        compile_best="n/a"
        wall_best="$wall_secs"
      fi
    elif [ "$driver" = "binink" ]; then
      local wall_start wall_end wall_secs stdout_file
      stdout_file="$TMP/stdout.$i"
      wall_start=$(date +%s%N)
      binink exec $BININK_OPTS benchmarks . "$file" run-benchmark >"$stdout_file" 2>&1
      wall_end=$(date +%s%N)
      wall_secs=$(awk "BEGIN{printf \"%.3f\", ($wall_end - $wall_start) / 1000000000}")
      # Parse Chez time output (elapsed real time) from stdout
      local mt
      mt=$(sed -n 's/^[[:space:]]*\([0-9.]*\)s elapsed real time.*/\1/p' "$stdout_file" | tail -1)
      times="$times $mt"
      if [ -z "$best" ] || awk "BEGIN{exit !($mt < $best)}"; then
        best="$mt"
        wall_best="$wall_secs"
      fi
    elif [ "$driver" = "binink-aot" ]; then
      local compile_start compile_end compile_secs wall_start wall_end wall_secs exec_secs stdout_file
      local out_binary="$TMP/bench.$i.out"
      stdout_file="$TMP/stdout.$i"

      # Measure compile time
      compile_start=$(date +%s%N)
      if [ "$QUIET" = true ]; then
        binink compile $BININK_OPTS benchmarks . "$file" run-benchmark >/dev/null 2>&1
      else
        binink compile $BININK_OPTS benchmarks . "$file" run-benchmark
      fi
      compile_end=$(date +%s%N)
      compile_secs=$(awk "BEGIN{printf \"%.3f\", ($compile_end - $compile_start) / 1000000000}")

      # Measure execute time
      wall_start=$(date +%s%N)
      ./a.out >"$stdout_file" 2>&1
      wall_end=$(date +%s%N)
      exec_secs=$(awk "BEGIN{printf \"%.3f\", ($wall_end - $wall_start) / 1000000000}")

      # Parse Chez time output (elapsed real time) from stdout
      local mt
      mt=$(sed -n 's/^[[:space:]]*\([0-9.]*\)s elapsed real time.*/\1/p' "$stdout_file" | tail -1)
      times="$times $mt"
      compile_times="$compile_times $compile_secs"

      if [ -z "$best" ] || awk "BEGIN{exit !($mt < $best)}"; then
        best="$mt"
        compile_best="$compile_secs"
        wall_best="$exec_secs"
      fi

      # Clean up compiled artifacts
      rm -f a.out *.so *.wpo
    else
      local wall_start wall_end wall_secs stdout_file
      stdout_file="$TMP/stdout.$i"
      wall_start=$(date +%s%N)
      scheme $SCHEME_OPTS --script "$file" >"$stdout_file" 2>&1
      wall_end=$(date +%s%N)
      wall_secs=$(awk "BEGIN{printf \"%.3f\", ($wall_end - $wall_start) / 1000000000}")
      # Parse Chez time output (elapsed real time) from stdout
      local mt
      mt=$(sed -n 's/^[[:space:]]*\([0-9.]*\)s elapsed real time.*/\1/p' "$stdout_file" | tail -1)
      times="$times $mt"
      if [ -z "$best" ] || awk "BEGIN{exit !($mt < $best)}"; then
        best="$mt"
        wall_best="$wall_secs"
      fi
    fi
  done

  # Output structured result
  local display_label="${label#*|}"
  if [ "$driver" = "seedink" ] || [ "$driver" = "seedink2" ] || [ "$driver" = "binink-aot" ]; then
    printf "  %-42s  compile: %8ss  execute: %8ss  wall: %8ss" "$display_label" "$compile_best" "$best" "$wall_best"
    if [ "$iters" -gt 1 ]; then
      printf "  (best of %d)" "$iters"
    fi
    printf "\n"
  else
    local fmt_best
    fmt_best=$(awk "BEGIN{printf \"%.3f\", $best}")
    printf "  %-42s                     execute: %8ss  wall: %8ss" "$display_label" "$fmt_best" "$wall_best"
    if [ "$iters" -gt 1 ]; then
      printf "  (best of %d)" "$iters"
    fi
    printf "\n"
  fi

  # Stash for summary table (TAB-separated)
  printf "%s\t%s\t%s\t%s\t%s\n" "$label" "$driver" "${compile_best:-n/a}" "$best" "$wall_best" >> "$TMP/results.csv"
}

# Export environment variables for benchmarks
export SEED_NQUEEN="$NQ_N"
export SEED_COLLATZ="$COLLATZ_LIMIT"
export SEED_SPECIAL="$SPECIAL_LIMIT"
export SEED_ABACUS_DEPTH="$ABACUS_EXPR_DEPTH"
export SEED_ABACUS2_DEPTH="$ABACUS2_EXPR_DEPTH"
export SEED_GREMLIN_N="$GREMLIN_N"
export SEED_GREMLIN_E="$GREMLIN_E"

# ══════════════════════════════════════════════════════════════════════
#  Prepare benchmark driver scripts
# ══════════════════════════════════════════════════════════════════════

# Generate scheme driver scripts that import and call run-benchmark
{ printf '(import (chezscheme) (benchmarks n-queen n-queen))\n'
  cat benchmarks/base.body.scm
  if [ "$DEV" = true ]; then
    printf '(dev! #t)\n'
  else
    printf '(dev! #f)\n'
  fi
  printf '(run-benchmark)\n'
} > "$TMP/nq-chez.scm"

{ printf '(import (chezscheme) (benchmarks collatz collatz))\n'
  cat benchmarks/base.body.scm
  if [ "$DEV" = true ]; then
    printf '(dev! #t)\n'
  else
    printf '(dev! #f)\n'
  fi
  printf '(run-benchmark)\n'
} > "$TMP/mb-chez.scm"

{ printf '(import (chezscheme) (benchmarks abacus abacus))\n'
  printf '(import (only (match) match guard))\n'
  cat benchmarks/base.body.scm
  if [ "$DEV" = true ]; then
    printf '(dev! #t)\n'
  else
    printf '(dev! #f)\n'
  fi
  printf '(run-benchmark)\n'
} > "$TMP/ab-chez.scm"

{ printf '(import (chezscheme) (benchmarks abacus2 abacus2))\n'
  printf '(import (only (match) match guard))\n'
  cat benchmarks/base.body.scm
  if [ "$DEV" = true ]; then
    printf '(dev! #t)\n'
  else
    printf '(dev! #f)\n'
  fi
  printf '(run-benchmark)\n'
} > "$TMP/ab2-chez.scm"

{ printf '(import (chezscheme) (benchmarks gremlin gremlin))\n'
  cat benchmarks/base.body.scm
  if [ "$DEV" = true ]; then
    printf '(dev! #t)\n'
  else
    printf '(dev! #f)\n'
  fi
  printf '(run-benchmark)\n'
} > "$TMP/gr-chez.scm"

# ══════════════════════════════════════════════════════════════════════
#  Run
# ══════════════════════════════════════════════════════════════════════

> "$TMP/results.csv"   # reset

if [ "$ONLY" = "all" ] || [ "$ONLY" = "nqueens" ]; then
  echo "── N-Queens — exercising single CPU ──────────────────────────────"
  for driver in "${SELECTED_DRIVERS[@]}"; do
    if [ "$driver" = "seedink" ]; then
      run_bench "N-Queens|scheme --script seedink.scm n-queen.seed" seedink "benchmarks/n-queen/n-queen.seed" "$ITERS"
    elif [ "$driver" = "seedink2" ]; then
      run_bench "N-Queens|scheme --script seedink2.scm n-queen.seed" seedink2 "benchmarks/n-queen/n-queen.seed" "$ITERS"
    elif [ "$driver" = "binink" ]; then
      run_bench "N-Queens|binink exec n-queen.binink.scm" binink "benchmarks/n-queen/n-queen.scm" "$ITERS"
    elif [ "$driver" = "binink-aot" ]; then
      run_bench "N-Queens|binink compile n-queen.binink.scm" binink-aot "benchmarks/n-queen/n-queen.scm" "$ITERS"
    else  # scheme
      run_bench "N-Queens|scheme --script n-queen.scm" scheme "$TMP/nq-chez.scm" "$ITERS"
    fi
  done
  echo
fi

if [ "$ONLY" = "all" ] || [ "$ONLY" = "collatz" ]; then
  echo "── Collatz — exercising syntax-rules ────────────────────────────"
  for driver in "${SELECTED_DRIVERS[@]}"; do
    if [ "$driver" = "seedink" ]; then
      run_bench "Collatz|scheme --script seedink.scm collatz.seed" seedink "benchmarks/collatz/collatz.seed" "$ITERS"
    elif [ "$driver" = "seedink2" ]; then
      run_bench "Collatz|scheme --script seedink2.scm collatz.seed" seedink2 "benchmarks/collatz/collatz.seed" "$ITERS"
    elif [ "$driver" = "binink" ]; then
      run_bench "Collatz|binink exec collatz.binink.scm" binink "benchmarks/collatz/collatz.scm" "$ITERS"
    elif [ "$driver" = "binink-aot" ]; then
      run_bench "Collatz|binink compile collatz.binink.scm" binink-aot "benchmarks/collatz/collatz.scm" "$ITERS"
    else  # scheme
      run_bench "Collatz|scheme --script collatz.scm" scheme "$TMP/mb-chez.scm" "$ITERS"
    fi
  done
  echo
fi

if [ "$ONLY" = "all" ] || [ "$ONLY" = "abacus" ]; then
  echo "── Abacus — exercising syntax-case ───────────────────────────────"

  for driver in "${SELECTED_DRIVERS[@]}"; do
    if [ "$driver" = "seedink" ]; then
  # Seed — parse compile/execute from stderr, tree/eval sub-timings from stdout
  seed_best="" seed_compile="" seed_tree="" seed_eval="" seed_wall=""
  for (( i=1; i<=ITERS; i++ )); do
    wall_start=$(date +%s%N)
    scheme $SCHEME_OPTS --script seedink.scm benchmarks/abacus/abacus.seed >"$TMP/ab-out.$i" 2>&1
    wall_end=$(date +%s%N)
    wall_secs=$(awk "BEGIN{printf \"%.3f\", ($wall_end - $wall_start) / 1000000000}")
    # Extract first two time values (tree build, then eval) - ignore third (outer time from run-file)
    times_arr=($(sed -n 's/^[[:space:]]*\([0-9.]*\)s elapsed real time.*/\1/p' "$TMP/ab-out.$i" | head -2))
    seed_tree="${times_arr[0]:-0}"
    seed_eval="${times_arr[1]:-0}"
    et=$(awk "BEGIN{printf \"%.6f\", $seed_tree + $seed_eval}")
    if [ -z "$seed_best" ] || awk "BEGIN{exit !($et < $seed_best)}"; then
      seed_best="$et"; seed_compile="n/a"; seed_wall="$wall_secs"
    fi
  done
  printf "  %-42s  compile: %8ss  tree: %8ss  eval: %8ss  wall: %8ss" \
         "scheme --script seedink.scm abacus.seed" "$seed_compile" "$seed_tree" "$seed_eval" "$seed_wall"
  [ "$ITERS" -gt 1 ] && printf "  (best of %d)" "$ITERS"
  printf "\n"
  # Stash seedink result for summary table
  printf "%s\t%s\t%s\t%s\t%s\n" "Abacus|scheme --script seedink.scm abacus.seed" "seedink" "$seed_compile" "$seed_best" "$seed_wall" >> "$TMP/results.csv"

    elif [ "$driver" = "seedink2" ]; then
  # Seed2 — same as seedink but uses seedink2.scm
  seed_best="" seed_compile="" seed_tree="" seed_eval="" seed_wall=""
  for (( i=1; i<=ITERS; i++ )); do
    wall_start=$(date +%s%N)
    scheme $SCHEME_OPTS --script seedink2.scm benchmarks/abacus/abacus.seed >"$TMP/ab-out.$i" 2>&1
    wall_end=$(date +%s%N)
    wall_secs=$(awk "BEGIN{printf \"%.3f\", ($wall_end - $wall_start) / 1000000000}")
    times_arr=($(sed -n 's/^[[:space:]]*\([0-9.]*\)s elapsed real time.*/\1/p' "$TMP/ab-out.$i" | head -2))
    seed_tree="${times_arr[0]:-0}"
    seed_eval="${times_arr[1]:-0}"
    et=$(awk "BEGIN{printf \"%.6f\", $seed_tree + $seed_eval}")
    if [ -z "$seed_best" ] || awk "BEGIN{exit !($et < $seed_best)}"; then
      seed_best="$et"; seed_compile="n/a"; seed_wall="$wall_secs"
    fi
  done
  printf "  %-42s  compile: %8ss  tree: %8ss  eval: %8ss  wall: %8ss" \
         "scheme --script seedink2.scm abacus.seed" "$seed_compile" "$seed_tree" "$seed_eval" "$seed_wall"
  [ "$ITERS" -gt 1 ] && printf "  (best of %d)" "$ITERS"
  printf "\n"
  printf "%s\t%s\t%s\t%s\t%s\n" "Abacus|scheme --script seedink2.scm abacus.seed" "seedink2" "$seed_compile" "$seed_best" "$seed_wall" >> "$TMP/results.csv"

    elif [ "$driver" = "binink" ]; then
  # binink exec — parse tree/eval from stdout
  binink_best="" binink_tree="" binink_eval="" binink_wall=""
  for (( i=1; i<=ITERS; i++ )); do
    wall_start=$(date +%s%N)
    binink exec $BININK_OPTS benchmarks . benchmarks/abacus/abacus.scm run-benchmark >"$TMP/ab-out.$i" 2>&1
    wall_end=$(date +%s%N)
    wall_secs=$(awk "BEGIN{printf \"%.3f\", ($wall_end - $wall_start) / 1000000000}")

    # Extract both time values (tree build first, then eval)
    times_arr=($(sed -n 's/^[[:space:]]*\([0-9.]*\)s elapsed real time.*/\1/p' "$TMP/ab-out.$i"))
    tree_s="${times_arr[0]:-0}"
    eval_s="${times_arr[1]:-0}"
    mt=$(awk "BEGIN{printf \"%.6f\", $tree_s + $eval_s}")

    if [ -z "$binink_best" ] || awk "BEGIN{exit !($mt < $binink_best)}"; then
      binink_best="$mt"; binink_wall="$wall_secs"
      binink_tree="$tree_s"
      binink_eval="$eval_s"
    fi
  done
  printf "  %-42s                      tree: %8ss  eval: %8ss  wall: %8ss" \
         "binink exec abacus.binink.scm" "$binink_tree" "$binink_eval" "$binink_wall"
  [ "$ITERS" -gt 1 ] && printf "  (best of %d)" "$ITERS"
  printf "\n"
  printf "%s\t%s\t%s\t%s\t%s\n" "Abacus|binink exec abacus.binink.scm" "binink" "n/a" "$binink_best" "$binink_wall" >> "$TMP/results.csv"

    elif [ "$driver" = "binink-aot" ]; then
  # binink-aot — compile, then execute with tree/eval parsing
  binink_aot_best="" binink_aot_compile="" binink_aot_tree="" binink_aot_eval="" binink_aot_wall=""
  for (( i=1; i<=ITERS; i++ )); do
    # Compile phase
    compile_start=$(date +%s%N)
    if [ "$QUIET" = true ]; then
      binink compile $BININK_OPTS benchmarks . benchmarks/abacus/abacus.scm run-benchmark >/dev/null 2>&1
    else
      binink compile $BININK_OPTS benchmarks . benchmarks/abacus/abacus.scm run-benchmark
    fi
    compile_end=$(date +%s%N)
    compile_secs=$(awk "BEGIN{printf \"%.3f\", ($compile_end - $compile_start) / 1000000000}")

    # Execute phase
    wall_start=$(date +%s%N)
    ./a.out >"$TMP/ab-out.$i" 2>&1
    wall_end=$(date +%s%N)
    exec_secs=$(awk "BEGIN{printf \"%.3f\", ($wall_end - $wall_start) / 1000000000}")

    # Extract both time values (tree build first, then eval) from stdout
    times_arr=($(sed -n 's/^[[:space:]]*\([0-9.]*\)s elapsed real time.*/\1/p' "$TMP/ab-out.$i"))
    tree_s="${times_arr[0]:-0}"
    eval_s="${times_arr[1]:-0}"
    mt=$(awk "BEGIN{printf \"%.6f\", $tree_s + $eval_s}")

    if [ -z "$binink_aot_best" ] || awk "BEGIN{exit !($mt < $binink_aot_best)}"; then
      binink_aot_best="$mt"
      binink_aot_compile="$compile_secs"
      binink_aot_wall="$exec_secs"
      binink_aot_tree="$tree_s"
      binink_aot_eval="$eval_s"
    fi

    # Clean up compiled artifacts
    rm -f a.out *.so *.wpo
  done
  printf "  %-42s  compile: %8ss  tree: %8ss  eval: %8ss  wall: %8ss" \
         "binink compile abacus.binink.scm" "$binink_aot_compile" "$binink_aot_tree" "$binink_aot_eval" "$binink_aot_wall"
  [ "$ITERS" -gt 1 ] && printf "  (best of %d)" "$ITERS"
  printf "\n"
  printf "%s\t%s\t%s\t%s\t%s\n" "Abacus|binink compile abacus.binink.scm" "binink-aot" "$binink_aot_compile" "$binink_aot_best" "$binink_aot_wall" >> "$TMP/results.csv"

    elif [ "$driver" = "scheme" ]; then
  # Chez — parse tree/eval sub-timings from stdout
  chez_best="" chez_tree="" chez_eval="" chez_wall=""
  for (( i=1; i<=ITERS; i++ )); do
    wall_start=$(date +%s%N)
    scheme $SCHEME_OPTS --script "$TMP/ab-chez.scm" >"$TMP/ab-out.$i" 2>&1
    wall_end=$(date +%s%N)
    wall_secs=$(awk "BEGIN{printf \"%.3f\", ($wall_end - $wall_start) / 1000000000}")
    # Extract both time values (tree build first, then eval) from stdout
    times_arr=($(sed -n 's/^[[:space:]]*\([0-9.]*\)s elapsed real time.*/\1/p' "$TMP/ab-out.$i"))
    tree_s="${times_arr[0]:-0}"
    eval_s="${times_arr[1]:-0}"
    mt=$(awk "BEGIN{printf \"%.6f\", $tree_s + $eval_s}")
    if [ -z "$chez_best" ] || awk "BEGIN{exit !($mt < $chez_best)}"; then
      chez_best="$mt"; chez_tree="$tree_s"; chez_eval="$eval_s"; chez_wall="$wall_secs"
    fi
  done
  chez_tree_fmt=$(awk "BEGIN{printf \"%.3f\", $chez_tree}")
  chez_eval_fmt=$(awk "BEGIN{printf \"%.3f\", $chez_eval}")
  printf "  %-42s                      tree: %8ss  eval: %8ss  wall: %8ss" \
         "scheme --script abacus.scm" "$chez_tree_fmt" "$chez_eval_fmt" "$chez_wall"
  [ "$ITERS" -gt 1 ] && printf "  (best of %d)" "$ITERS"
  printf "\n"
  # Stash scheme result for summary table
  printf "%s\t%s\t%s\t%s\t%s\n" "Abacus|scheme --script abacus.scm" "scheme" "n/a" "$chez_best" "$chez_wall" >> "$TMP/results.csv"
    fi
  done
  echo
fi

if [ "$ONLY" = "all" ] || [ "$ONLY" = "abacus2" ]; then
  echo "── Abacus2 — multi-operand match (ternary trees) ─────────────────"

  for driver in "${SELECTED_DRIVERS[@]}"; do
    if [ "$driver" = "seedink" ]; then
  # Seed — parse compile/execute from stderr, tree/eval sub-timings from stdout
  seed_best="" seed_compile="" seed_tree="" seed_eval="" seed_wall=""
  for (( i=1; i<=ITERS; i++ )); do
    wall_start=$(date +%s%N)
    scheme $SCHEME_OPTS --script seedink.scm benchmarks/abacus2/abacus2.seed >"$TMP/ab2-out.$i" 2>&1
    wall_end=$(date +%s%N)
    wall_secs=$(awk "BEGIN{printf \"%.3f\", ($wall_end - $wall_start) / 1000000000}")
    # Extract first two time values (tree build, then eval) - ignore third (outer time from run-file)
    times_arr=($(sed -n 's/^[[:space:]]*\([0-9.]*\)s elapsed real time.*/\1/p' "$TMP/ab2-out.$i" | head -2))
    seed_tree="${times_arr[0]:-0}"
    seed_eval="${times_arr[1]:-0}"
    et=$(awk "BEGIN{printf \"%.6f\", $seed_tree + $seed_eval}")
    if [ -z "$seed_best" ] || awk "BEGIN{exit !($et < $seed_best)}"; then
      seed_best="$et"; seed_compile="n/a"; seed_wall="$wall_secs"
    fi
  done
  printf "  %-42s  compile: %8ss  tree: %8ss  eval: %8ss  wall: %8ss" \
         "scheme --script seedink.scm abacus2.seed" "$seed_compile" "$seed_tree" "$seed_eval" "$seed_wall"
  [ "$ITERS" -gt 1 ] && printf "  (best of %d)" "$ITERS"
  printf "\n"
  # Stash seedink result for summary table
  printf "%s\t%s\t%s\t%s\t%s\n" "Abacus2|scheme --script seedink.scm abacus2.seed" "seedink" "$seed_compile" "$seed_best" "$seed_wall" >> "$TMP/results.csv"

    elif [ "$driver" = "seedink2" ]; then
  # Seed2 — same as seedink but uses seedink2.scm
  seed_best="" seed_compile="" seed_tree="" seed_eval="" seed_wall=""
  for (( i=1; i<=ITERS; i++ )); do
    wall_start=$(date +%s%N)
    scheme $SCHEME_OPTS --script seedink2.scm benchmarks/abacus2/abacus2.seed >"$TMP/ab2-out.$i" 2>&1
    wall_end=$(date +%s%N)
    wall_secs=$(awk "BEGIN{printf \"%.3f\", ($wall_end - $wall_start) / 1000000000}")
    times_arr=($(sed -n 's/^[[:space:]]*\([0-9.]*\)s elapsed real time.*/\1/p' "$TMP/ab2-out.$i" | head -2))
    seed_tree="${times_arr[0]:-0}"
    seed_eval="${times_arr[1]:-0}"
    et=$(awk "BEGIN{printf \"%.6f\", $seed_tree + $seed_eval}")
    if [ -z "$seed_best" ] || awk "BEGIN{exit !($et < $seed_best)}"; then
      seed_best="$et"; seed_compile="n/a"; seed_wall="$wall_secs"
    fi
  done
  printf "  %-42s  compile: %8ss  tree: %8ss  eval: %8ss  wall: %8ss" \
         "scheme --script seedink2.scm abacus2.seed" "$seed_compile" "$seed_tree" "$seed_eval" "$seed_wall"
  [ "$ITERS" -gt 1 ] && printf "  (best of %d)" "$ITERS"
  printf "\n"
  printf "%s\t%s\t%s\t%s\t%s\n" "Abacus2|scheme --script seedink2.scm abacus2.seed" "seedink2" "$seed_compile" "$seed_best" "$seed_wall" >> "$TMP/results.csv"

    elif [ "$driver" = "binink" ]; then
  # binink exec — parse tree/eval from stdout
  binink_best="" binink_tree="" binink_eval="" binink_wall=""
  for (( i=1; i<=ITERS; i++ )); do
    wall_start=$(date +%s%N)
    binink exec $BININK_OPTS benchmarks . benchmarks/abacus2/abacus2.scm run-benchmark >"$TMP/ab2-out.$i" 2>&1
    wall_end=$(date +%s%N)
    wall_secs=$(awk "BEGIN{printf \"%.3f\", ($wall_end - $wall_start) / 1000000000}")

    # Extract both time values (tree build first, then eval) from stdout
    times_arr=($(sed -n 's/^[[:space:]]*\([0-9.]*\)s elapsed real time.*/\1/p' "$TMP/ab2-out.$i"))
    tree_s="${times_arr[0]:-0}"
    eval_s="${times_arr[1]:-0}"
    mt=$(awk "BEGIN{printf \"%.6f\", $tree_s + $eval_s}")

    if [ -z "$binink_best" ] || awk "BEGIN{exit !($mt < $binink_best)}"; then
      binink_best="$mt"; binink_wall="$wall_secs"
      binink_tree="$tree_s"
      binink_eval="$eval_s"
    fi
  done
  printf "  %-42s                      tree: %8ss  eval: %8ss  wall: %8ss" \
         "binink exec abacus2.binink.scm" "$binink_tree" "$binink_eval" "$binink_wall"
  [ "$ITERS" -gt 1 ] && printf "  (best of %d)" "$ITERS"
  printf "\n"
  printf "%s\t%s\t%s\t%s\t%s\n" "Abacus2|binink exec abacus2.binink.scm" "binink" "n/a" "$binink_best" "$binink_wall" >> "$TMP/results.csv"

    elif [ "$driver" = "binink-aot" ]; then
  # binink-aot — compile, then execute with tree/eval parsing
  binink_aot_best="" binink_aot_compile="" binink_aot_tree="" binink_aot_eval="" binink_aot_wall=""
  for (( i=1; i<=ITERS; i++ )); do
    # Compile phase
    compile_start=$(date +%s%N)
    if [ "$QUIET" = true ]; then
      binink compile $BININK_OPTS benchmarks . benchmarks/abacus2/abacus2.scm run-benchmark >/dev/null 2>&1
    else
      binink compile $BININK_OPTS benchmarks . benchmarks/abacus2/abacus2.scm run-benchmark
    fi
    compile_end=$(date +%s%N)
    compile_secs=$(awk "BEGIN{printf \"%.3f\", ($compile_end - $compile_start) / 1000000000}")

    # Execute phase
    wall_start=$(date +%s%N)
    ./a.out >"$TMP/ab2-out.$i" 2>&1
    wall_end=$(date +%s%N)
    exec_secs=$(awk "BEGIN{printf \"%.3f\", ($wall_end - $wall_start) / 1000000000}")

    # Extract both time values (tree build first, then eval) from stdout
    times_arr=($(sed -n 's/^[[:space:]]*\([0-9.]*\)s elapsed real time.*/\1/p' "$TMP/ab2-out.$i"))
    tree_s="${times_arr[0]:-0}"
    eval_s="${times_arr[1]:-0}"
    mt=$(awk "BEGIN{printf \"%.6f\", $tree_s + $eval_s}")

    if [ -z "$binink_aot_best" ] || awk "BEGIN{exit !($mt < $binink_aot_best)}"; then
      binink_aot_best="$mt"
      binink_aot_compile="$compile_secs"
      binink_aot_wall="$exec_secs"
      binink_aot_tree="$tree_s"
      binink_aot_eval="$eval_s"
    fi

    # Clean up compiled artifacts
    rm -f a.out *.so *.wpo
  done
  printf "  %-42s  compile: %8ss  tree: %8ss  eval: %8ss  wall: %8ss" \
         "binink compile abacus2.binink.scm" "$binink_aot_compile" "$binink_aot_tree" "$binink_aot_eval" "$binink_aot_wall"
  [ "$ITERS" -gt 1 ] && printf "  (best of %d)" "$ITERS"
  printf "\n"
  printf "%s\t%s\t%s\t%s\t%s\n" "Abacus2|binink compile abacus2.binink.scm" "binink-aot" "$binink_aot_compile" "$binink_aot_best" "$binink_aot_wall" >> "$TMP/results.csv"

    elif [ "$driver" = "scheme" ]; then
  # Chez — parse tree/eval sub-timings from stdout
  chez_best="" chez_tree="" chez_eval="" chez_wall=""
  for (( i=1; i<=ITERS; i++ )); do
    wall_start=$(date +%s%N)
    scheme $SCHEME_OPTS --script "$TMP/ab2-chez.scm" >"$TMP/ab2-out.$i" 2>&1
    wall_end=$(date +%s%N)
    wall_secs=$(awk "BEGIN{printf \"%.3f\", ($wall_end - $wall_start) / 1000000000}")
    # Extract both time values (tree build first, then eval) from stdout
    times_arr=($(sed -n 's/^[[:space:]]*\([0-9.]*\)s elapsed real time.*/\1/p' "$TMP/ab2-out.$i"))
    tree_s="${times_arr[0]:-0}"
    eval_s="${times_arr[1]:-0}"
    mt=$(awk "BEGIN{printf \"%.6f\", $tree_s + $eval_s}")
    if [ -z "$chez_best" ] || awk "BEGIN{exit !($mt < $chez_best)}"; then
      chez_best="$mt"; chez_tree="$tree_s"; chez_eval="$eval_s"; chez_wall="$wall_secs"
    fi
  done
  chez_tree_fmt=$(awk "BEGIN{printf \"%.3f\", $chez_tree}")
  chez_eval_fmt=$(awk "BEGIN{printf \"%.3f\", $chez_eval}")
  printf "  %-42s                      tree: %8ss  eval: %8ss  wall: %8ss" \
         "scheme --script abacus2.scm" "$chez_tree_fmt" "$chez_eval_fmt" "$chez_wall"
  [ "$ITERS" -gt 1 ] && printf "  (best of %d)" "$ITERS"
  printf "\n"
  # Stash scheme result for summary table
  printf "%s\t%s\t%s\t%s\t%s\n" "Abacus2|scheme --script abacus2.scm" "scheme" "n/a" "$chez_best" "$chez_wall" >> "$TMP/results.csv"
    fi
  done
  echo
fi

if [ "$ONLY" = "all" ] || [ "$ONLY" = "gremlin" ]; then
  echo "── Gremlin — exercising (values news out) convention ──────────────"

  for driver in "${SELECTED_DRIVERS[@]}"; do
    if [ "$driver" = "seedink2" ]; then
      run_bench "Gremlin|scheme --script seedink2.scm gremlin.seed2" seedink2 "benchmarks/gremlin/gremlin.seed2" "$ITERS"
    elif [ "$driver" = "scheme" ]; then
      run_bench "Gremlin|scheme --script gremlin.scm" scheme "$TMP/gr-chez.scm" "$ITERS"
    fi
    # seedink/binink not supported for .seed2 benchmarks
  done
  echo
fi

# ══════════════════════════════════════════════════════════════════════
#  Summary table
# ══════════════════════════════════════════════════════════════════════

echo "── Summary ────────────────────────────────────────────────────────"
printf "%-20s  %-15s  %12s  %12s\n" \
       "Benchmark" "Driver" "Monotonic" "Wall Clock"
printf "%-20s  %-15s  %12s  %12s\n" \
       "────────────────────" "───────────────" "────────────" "────────────"

# Parse results and organize by benchmark and driver
declare -A results  # results[benchmark:driver]="monotonic|wall"
declare -a bench_list driver_list_unique

while IFS=$'\t' read -r label driver ct et wall; do
  bench="${label%%|*}"

  # Store result
  results["$bench:$driver"]="$et|$wall"

  # Track unique benchmarks
  if [[ ! " ${bench_list[@]} " =~ " ${bench} " ]]; then
    bench_list+=("$bench")
  fi

  # Track unique drivers (in order seen)
  if [[ ! " ${driver_list_unique[@]} " =~ " ${driver} " ]]; then
    driver_list_unique+=("$driver")
  fi
done < "$TMP/results.csv"

# Initialize totals for each driver
declare -A driver_totals_mono driver_totals_wall
for driver in "${driver_list_unique[@]}"; do
  driver_totals_mono[$driver]="0"
  driver_totals_wall[$driver]="0"
done

# Print results for each benchmark/driver combination
for bench in "${bench_list[@]}"; do
  for driver in "${SELECTED_DRIVERS[@]}"; do
    result="${results[$bench:$driver]:-}"
    if [ -n "$result" ]; then
      IFS='|' read -r mono wall <<< "$result"
      printf "%-20s  %-15s  %11ss  %11ss\n" \
             "$bench" "$driver" \
             "$(awk -v v="$mono" 'BEGIN{printf "%.3f", v}')" \
             "$wall"

      # Accumulate totals
      driver_totals_mono[$driver]=$(awk -v a="${driver_totals_mono[$driver]}" -v b="$mono" 'BEGIN{printf "%.6f", a + b}')
      driver_totals_wall[$driver]=$(awk -v a="${driver_totals_wall[$driver]}" -v b="$wall" 'BEGIN{printf "%.6f", a + b}')
    fi
  done
done

# Print separator and totals
printf "%-20s  %-15s  %12s  %12s\n" \
       "────────────────────" "───────────────" "────────────" "────────────"

for driver in "${SELECTED_DRIVERS[@]}"; do
  if [ -n "${driver_totals_mono[$driver]:-}" ]; then
    printf "%-20s  %-15s  %11ss  %11ss\n" \
           "TOTAL" "$driver" \
           "$(awk -v v="${driver_totals_mono[$driver]}" 'BEGIN{printf "%.3f", v}')" \
           "$(awk -v v="${driver_totals_wall[$driver]}" 'BEGIN{printf "%.3f", v}')"
  fi
done
