#!/bin/bash
set -euo pipefail

###############################################################################
# model_benchmark.sh — Benchmark Python script execution with timing/memory
# Usage: model_benchmark.sh <python_script> [args...] [--output=benchmark_results.json]
# Exit codes: 0=OK, 1=issues found, 2=error
###############################################################################

if [[ $# -lt 1 ]]; then
  cat <<EOF
Usage: $(basename "$0") <python_script> [args...] [--output=FILE]

  python_script   Path to the Python script to benchmark
  --output=FILE   Output file for results (default: benchmark_results.json)
  --label=NAME    Label for this benchmark run
  --iterations=N  Number of iterations (default: 1)

Examples:
  $(basename "$0") train.py --epochs=10
  $(basename "$0") inference.py --output=results.json --label="v2-optimized"
EOF
  exit 2
fi

# --- Parse arguments ---
SCRIPT_PATH=""
SCRIPT_ARGS=()
OUTPUT_FILE="benchmark_results.json"
LABEL=""
ITERATIONS=1

for arg in "$@"; do
  case "$arg" in
    --output=*)  OUTPUT_FILE="${arg#--output=}" ;;
    --label=*)   LABEL="${arg#--label=}" ;;
    --iterations=*) ITERATIONS="${arg#--iterations=}" ;;
    *)
      if [[ -z "$SCRIPT_PATH" ]]; then
        SCRIPT_PATH="$arg"
      else
        SCRIPT_ARGS+=("$arg")
      fi
      ;;
  esac
done

if [[ -z "$SCRIPT_PATH" ]]; then
  echo "ERROR: Python script path is required." >&2
  exit 2
fi

if [[ ! -f "$SCRIPT_PATH" ]]; then
  echo "ERROR: Script '$SCRIPT_PATH' not found." >&2
  exit 2
fi

if [[ -z "$LABEL" ]]; then
  LABEL="$(basename "$SCRIPT_PATH" .py)-$(date +%Y%m%d-%H%M%S)"
fi

PROJECT_PATH="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Resolve output file path
if [[ ! "$OUTPUT_FILE" = /* ]]; then
  OUTPUT_FILE="$PROJECT_PATH/$OUTPUT_FILE"
fi

echo "=============================================="
echo " Model Benchmark"
echo " Script: $SCRIPT_PATH"
echo " Label:  $LABEL"
echo " Iterations: $ITERATIONS"
echo "=============================================="
echo ""

# --- Detect measurement tools ---
USE_TIME_V=false
if /usr/bin/time -v echo "test" &>/dev/null 2>&1; then
  USE_TIME_V=true
fi

PYTHON_CMD="python3"
if ! command -v python3 &>/dev/null; then
  PYTHON_CMD="python"
fi

# --- Run benchmarks ---
RESULTS=()
TOTAL_TIME=0
PEAK_MEM=0

for i in $(seq 1 "$ITERATIONS"); do
  echo "  --- Iteration $i/$ITERATIONS ---"

  if $USE_TIME_V; then
    # Use /usr/bin/time -v for detailed stats
    TIME_OUTPUT=$(mktemp)
    SCRIPT_OUTPUT=$(mktemp)

    START_TS=$(date +%s%N)
    /usr/bin/time -v "$PYTHON_CMD" "$SCRIPT_PATH" "${SCRIPT_ARGS[@]}" \
      > "$SCRIPT_OUTPUT" 2> "$TIME_OUTPUT" || true
    END_TS=$(date +%s%N)

    WALL_TIME_NS=$((END_TS - START_TS))
    WALL_TIME_SEC=$(echo "scale=3; $WALL_TIME_NS / 1000000000" | bc)

    # Parse /usr/bin/time output
    USER_TIME=$(grep "User time" "$TIME_OUTPUT" | grep -oP '[\d.]+' | tail -1 || echo "0")
    SYS_TIME=$(grep "System time" "$TIME_OUTPUT" | grep -oP '[\d.]+' | tail -1 || echo "0")
    MAX_RSS=$(grep "Maximum resident" "$TIME_OUTPUT" | grep -oP '[\d]+' | tail -1 || echo "0")
    EXIT_CODE=$(grep "Exit status" "$TIME_OUTPUT" | grep -oP '[\d]+' | tail -1 || echo "0")

    # Convert RSS from KB to MB
    MAX_RSS_MB=$(echo "scale=1; $MAX_RSS / 1024" | bc 2>/dev/null || echo "0")

    echo "  Wall time:    ${WALL_TIME_SEC}s"
    echo "  User time:    ${USER_TIME}s"
    echo "  System time:  ${SYS_TIME}s"
    echo "  Peak memory:  ${MAX_RSS_MB}MB"
    echo "  Exit code:    $EXIT_CODE"

    # Track peak
    CURRENT_MEM_KB=$MAX_RSS
    if [[ $CURRENT_MEM_KB -gt $PEAK_MEM ]]; then
      PEAK_MEM=$CURRENT_MEM_KB
    fi

    rm -f "$TIME_OUTPUT" "$SCRIPT_OUTPUT"

  else
    # Fallback: use Python resource module
    START_TS=$(date +%s%N)

    BENCH_OUTPUT=$("$PYTHON_CMD" -c "
import resource
import subprocess
import sys
import time
import json

start = time.time()
result = subprocess.run(
    [sys.executable, '$SCRIPT_PATH'] + $(printf "'%s'," "${SCRIPT_ARGS[@]}" | sed 's/,$//' | sed 's/^/[/;s/$/]/'),
    capture_output=True, text=True
)
end = time.time()

usage = resource.getrusage(resource.RUSAGE_CHILDREN)
print(json.dumps({
    'wall_time': round(end - start, 3),
    'user_time': round(usage.ru_utime, 3),
    'sys_time': round(usage.ru_stime, 3),
    'max_rss_kb': usage.ru_maxrss,
    'exit_code': result.returncode
}))
" 2>/dev/null || echo '{"wall_time":0,"user_time":0,"sys_time":0,"max_rss_kb":0,"exit_code":1}')

    END_TS=$(date +%s%N)
    WALL_TIME_NS=$((END_TS - START_TS))
    WALL_TIME_SEC=$(echo "scale=3; $WALL_TIME_NS / 1000000000" | bc)

    WALL_TIME=$(echo "$BENCH_OUTPUT" | "$PYTHON_CMD" -c "import sys,json; print(json.loads(sys.stdin.read())['wall_time'])" 2>/dev/null || echo "$WALL_TIME_SEC")
    USER_TIME=$(echo "$BENCH_OUTPUT" | "$PYTHON_CMD" -c "import sys,json; print(json.loads(sys.stdin.read())['user_time'])" 2>/dev/null || echo "0")
    SYS_TIME=$(echo "$BENCH_OUTPUT" | "$PYTHON_CMD" -c "import sys,json; print(json.loads(sys.stdin.read())['sys_time'])" 2>/dev/null || echo "0")
    MAX_RSS=$(echo "$BENCH_OUTPUT" | "$PYTHON_CMD" -c "import sys,json; print(json.loads(sys.stdin.read())['max_rss_kb'])" 2>/dev/null || echo "0")
    EXIT_CODE=$(echo "$BENCH_OUTPUT" | "$PYTHON_CMD" -c "import sys,json; print(json.loads(sys.stdin.read())['exit_code'])" 2>/dev/null || echo "0")

    MAX_RSS_MB=$(echo "scale=1; $MAX_RSS / 1024" | bc 2>/dev/null || echo "0")

    echo "  Wall time:    ${WALL_TIME}s"
    echo "  User time:    ${USER_TIME}s"
    echo "  System time:  ${SYS_TIME}s"
    echo "  Peak memory:  ${MAX_RSS_MB}MB"
    echo "  Exit code:    $EXIT_CODE"

    CURRENT_MEM_KB=$MAX_RSS
    if [[ $CURRENT_MEM_KB -gt $PEAK_MEM ]]; then
      PEAK_MEM=$CURRENT_MEM_KB
    fi
  fi

  echo ""
done

# --- Save results to JSON ---
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
PEAK_MEM_MB=$(echo "scale=1; $PEAK_MEM / 1024" | bc 2>/dev/null || echo "0")

# Append to existing results file or create new
"$PYTHON_CMD" - "$OUTPUT_FILE" "$LABEL" "$SCRIPT_PATH" "$TIMESTAMP" "$WALL_TIME_SEC" "$USER_TIME" "$SYS_TIME" "$PEAK_MEM_MB" "$EXIT_CODE" "$ITERATIONS" <<'PYSAVE'
import sys
import json
import os

output_file = sys.argv[1]
label = sys.argv[2]
script = sys.argv[3]
timestamp = sys.argv[4]
wall_time = float(sys.argv[5])
user_time = float(sys.argv[6])
sys_time = float(sys.argv[7])
peak_mem = float(sys.argv[8])
exit_code = int(sys.argv[9])
iterations = int(sys.argv[10])

new_entry = {
    "label": label,
    "script": script,
    "timestamp": timestamp,
    "iterations": iterations,
    "wall_time_sec": wall_time,
    "user_time_sec": user_time,
    "sys_time_sec": sys_time,
    "peak_memory_mb": peak_mem,
    "exit_code": exit_code
}

# Load existing results
results = []
if os.path.exists(output_file):
    try:
        with open(output_file, 'r') as f:
            data = json.load(f)
            if isinstance(data, list):
                results = data
            elif isinstance(data, dict) and "benchmarks" in data:
                results = data["benchmarks"]
    except (json.JSONDecodeError, IOError):
        pass

results.append(new_entry)

with open(output_file, 'w') as f:
    json.dump({"benchmarks": results}, f, indent=2)

print(f"  Results saved to: {output_file}")

# Show comparison if previous results exist
if len(results) > 1:
    prev = results[-2]
    print(f"")
    print(f"  ## Comparison with previous run")
    print(f"  Previous: {prev['label']} ({prev['timestamp']})")
    print(f"")
    time_diff = wall_time - prev['wall_time_sec']
    time_pct = (time_diff / prev['wall_time_sec'] * 100) if prev['wall_time_sec'] > 0 else 0
    sign = "+" if time_diff > 0 else ""
    print(f"  Wall time:  {sign}{time_diff:.3f}s ({sign}{time_pct:.1f}%)")
    mem_diff = peak_mem - prev['peak_memory_mb']
    mem_pct = (mem_diff / prev['peak_memory_mb'] * 100) if prev['peak_memory_mb'] > 0 else 0
    sign = "+" if mem_diff > 0 else ""
    print(f"  Peak mem:   {sign}{mem_diff:.1f}MB ({sign}{mem_pct:.1f}%)")
PYSAVE

echo ""
echo "=============================================="
echo " Benchmark complete"
echo "=============================================="
exit 0
