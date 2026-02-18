#!/bin/bash
set -euo pipefail

###############################################################################
# data_profile.sh — Profile CSV/JSON data files with statistics
# Usage: data_profile.sh <data_file> [project_path]
# Exit codes: 0=OK, 1=issues found, 2=error
###############################################################################

if [[ $# -lt 1 ]]; then
  echo "Usage: $(basename "$0") <data_file> [project_path]" >&2
  echo "  Supports: .csv, .json, .jsonl" >&2
  exit 2
fi

DATA_FILE="$1"
PROJECT_PATH="${2:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# Resolve relative path
if [[ ! "$DATA_FILE" = /* ]]; then
  DATA_FILE="$PROJECT_PATH/$DATA_FILE"
fi

if [[ ! -f "$DATA_FILE" ]]; then
  echo "ERROR: File '$DATA_FILE' not found." >&2
  exit 2
fi

FILE_EXT="${DATA_FILE##*.}"
FILE_SIZE=$(stat -c%s "$DATA_FILE" 2>/dev/null || stat -f%z "$DATA_FILE" 2>/dev/null || echo "0")

human_size() {
  local bytes=$1
  if [[ $bytes -ge 1073741824 ]]; then
    echo "$(echo "scale=1; $bytes/1073741824" | bc)G"
  elif [[ $bytes -ge 1048576 ]]; then
    echo "$(echo "scale=1; $bytes/1048576" | bc)M"
  elif [[ $bytes -ge 1024 ]]; then
    echo "$(echo "scale=1; $bytes/1024" | bc)K"
  else
    echo "${bytes}B"
  fi
}

echo "=============================================="
echo " Data Profile Report"
echo " File: ${DATA_FILE}"
echo " Size: $(human_size "$FILE_SIZE")"
echo "=============================================="
echo ""

# --- CSV profiling ---
if [[ "$FILE_EXT" == "csv" || "$FILE_EXT" == "tsv" ]]; then

  # Try pandas first, fall back to stdlib
  python3 - "$DATA_FILE" "$FILE_EXT" <<'PYCSV'
import sys
import os

data_file = sys.argv[1]
file_ext = sys.argv[2]

try:
    import pandas as pd
    USE_PANDAS = True
except ImportError:
    USE_PANDAS = False

if USE_PANDAS:
    sep = '\t' if file_ext == 'tsv' else ','
    try:
        df = pd.read_csv(data_file, sep=sep, low_memory=False)
    except Exception as e:
        print(f"  ERROR reading file: {e}")
        sys.exit(1)

    print(f"## Overview")
    print(f"")
    print(f"  Rows:    {len(df):,}")
    print(f"  Columns: {len(df.columns)}")
    print(f"")

    print(f"## Column Details")
    print(f"")
    print(f"  {'Column':<30} {'Type':<15} {'Non-Null':<12} {'Null%':<8} {'Unique':<10} {'Sample'}")
    print(f"  {'-'*30} {'-'*15} {'-'*12} {'-'*8} {'-'*10} {'-'*20}")

    for col in df.columns:
        dtype = str(df[col].dtype)
        non_null = df[col].notna().sum()
        null_pct = f"{df[col].isna().mean()*100:.1f}%"
        unique = df[col].nunique()
        sample = str(df[col].dropna().iloc[0])[:20] if non_null > 0 else "N/A"
        print(f"  {str(col):<30} {dtype:<15} {non_null:<12} {null_pct:<8} {unique:<10} {sample}")

    print(f"")

    # Numeric stats
    numeric_cols = df.select_dtypes(include=['number']).columns
    if len(numeric_cols) > 0:
        print(f"## Numeric Statistics")
        print(f"")
        print(f"  {'Column':<30} {'Mean':<15} {'Median':<15} {'Min':<15} {'Max':<15} {'Std':<15}")
        print(f"  {'-'*30} {'-'*15} {'-'*15} {'-'*15} {'-'*15} {'-'*15}")

        for col in numeric_cols:
            mean = f"{df[col].mean():.2f}" if df[col].notna().any() else "N/A"
            median = f"{df[col].median():.2f}" if df[col].notna().any() else "N/A"
            mn = f"{df[col].min():.2f}" if df[col].notna().any() else "N/A"
            mx = f"{df[col].max():.2f}" if df[col].notna().any() else "N/A"
            std = f"{df[col].std():.2f}" if df[col].notna().any() else "N/A"
            print(f"  {str(col):<30} {mean:<15} {median:<15} {mn:<15} {mx:<15} {std:<15}")
        print(f"")

    # Sample rows
    print(f"## Sample Rows (first 5)")
    print(f"")
    print(df.head().to_string(index=False, max_colwidth=30))
    print(f"")

else:
    # Fallback: stdlib csv
    import csv
    import collections

    sep = '\t' if file_ext == 'tsv' else ','

    with open(data_file, 'r', newline='', errors='replace') as f:
        reader = csv.reader(f, delimiter=sep)
        headers = next(reader, None)
        if not headers:
            print("  ERROR: No headers found")
            sys.exit(1)

        rows = list(reader)

    print(f"## Overview")
    print(f"")
    print(f"  Rows:    {len(rows):,}")
    print(f"  Columns: {len(headers)}")
    print(f"")

    print(f"## Column Details")
    print(f"")
    print(f"  {'Column':<30} {'Non-Empty':<12} {'Null%':<8} {'Sample'}")
    print(f"  {'-'*30} {'-'*12} {'-'*8} {'-'*20}")

    for i, col in enumerate(headers):
        values = [row[i] for row in rows if i < len(row)]
        non_empty = sum(1 for v in values if v.strip())
        null_pct = f"{(1 - non_empty/len(values))*100:.1f}%" if values else "N/A"
        sample = values[0][:20] if values and values[0].strip() else "N/A"
        print(f"  {col:<30} {non_empty:<12} {null_pct:<8} {sample}")

    print(f"")

    # Numeric stats with stdlib
    print(f"## Numeric Statistics (stdlib)")
    print(f"")
    for i, col in enumerate(headers):
        values = []
        for row in rows:
            if i < len(row) and row[i].strip():
                try:
                    values.append(float(row[i]))
                except ValueError:
                    pass
        if values:
            values.sort()
            n = len(values)
            mean = sum(values) / n
            median = values[n//2] if n % 2 else (values[n//2-1] + values[n//2]) / 2
            print(f"  {col}: mean={mean:.2f}, median={median:.2f}, min={min(values):.2f}, max={max(values):.2f}, count={n}")
    print(f"")
PYCSV

# --- JSON profiling ---
elif [[ "$FILE_EXT" == "json" || "$FILE_EXT" == "jsonl" ]]; then

  python3 - "$DATA_FILE" "$FILE_EXT" <<'PYJSON'
import sys
import json
import collections

data_file = sys.argv[1]
file_ext = sys.argv[2]

def analyze_structure(obj, depth=0, max_depth=10):
    """Recursively analyze JSON structure."""
    if depth > max_depth:
        return {"type": "...", "depth": depth}

    if isinstance(obj, dict):
        result = {"type": "object", "keys": len(obj), "depth": depth, "children": {}}
        for k, v in list(obj.items())[:50]:  # Limit keys analyzed
            result["children"][k] = analyze_structure(v, depth + 1, max_depth)
        return result
    elif isinstance(obj, list):
        result = {"type": "array", "length": len(obj), "depth": depth}
        if obj:
            result["element"] = analyze_structure(obj[0], depth + 1, max_depth)
        return result
    elif isinstance(obj, str):
        return {"type": "string", "depth": depth}
    elif isinstance(obj, bool):
        return {"type": "boolean", "depth": depth}
    elif isinstance(obj, (int, float)):
        return {"type": "number", "depth": depth}
    elif obj is None:
        return {"type": "null", "depth": depth}
    return {"type": type(obj).__name__, "depth": depth}

def print_structure(struct, indent=0, name="root"):
    """Pretty print structure analysis."""
    prefix = "  " * indent + "  "
    t = struct.get("type", "?")

    if t == "object":
        keys = struct.get("keys", 0)
        print(f"{prefix}{name}: object ({keys} keys)")
        for k, v in struct.get("children", {}).items():
            print_structure(v, indent + 1, k)
    elif t == "array":
        length = struct.get("length", 0)
        print(f"{prefix}{name}: array (length: {length})")
        if "element" in struct:
            print_structure(struct["element"], indent + 1, "[element]")
    else:
        print(f"{prefix}{name}: {t}")

def get_max_depth(struct):
    if "children" in struct:
        return max((get_max_depth(v) for v in struct["children"].values()), default=struct["depth"])
    if "element" in struct:
        return get_max_depth(struct["element"])
    return struct.get("depth", 0)

try:
    if file_ext == "jsonl":
        records = []
        with open(data_file, 'r', errors='replace') as f:
            for line in f:
                line = line.strip()
                if line:
                    records.append(json.loads(line))

        print(f"## Overview (JSONL)")
        print(f"")
        print(f"  Records: {len(records):,}")
        print(f"")

        if records:
            # Key frequency across records
            key_counter = collections.Counter()
            for rec in records:
                if isinstance(rec, dict):
                    key_counter.update(rec.keys())

            print(f"## Key Frequency")
            print(f"")
            print(f"  {'Key':<30} {'Count':<10} {'%':<8} {'Sample Type'}")
            print(f"  {'-'*30} {'-'*10} {'-'*8} {'-'*15}")
            for key, count in key_counter.most_common(30):
                pct = f"{count/len(records)*100:.1f}%"
                sample_val = None
                for r in records:
                    if isinstance(r, dict) and key in r:
                        sample_val = r[key]
                        break
                stype = type(sample_val).__name__ if sample_val is not None else "null"
                print(f"  {key:<30} {count:<10} {pct:<8} {stype}")
            print(f"")

            # Structure of first record
            print(f"## Structure (first record)")
            print(f"")
            struct = analyze_structure(records[0])
            print_structure(struct)
            print(f"")

    else:
        with open(data_file, 'r', errors='replace') as f:
            data = json.load(f)

        print(f"## Structure Analysis")
        print(f"")

        struct = analyze_structure(data)
        max_depth = get_max_depth(struct)
        print(f"  Max depth: {max_depth}")
        print(f"  Root type: {struct['type']}")
        print(f"")

        print_structure(struct)
        print(f"")

        # If root is array, show element analysis
        if isinstance(data, list):
            print(f"## Array Analysis")
            print(f"")
            print(f"  Total elements: {len(data):,}")
            if data:
                if isinstance(data[0], dict):
                    key_counter = collections.Counter()
                    for item in data:
                        if isinstance(item, dict):
                            key_counter.update(item.keys())

                    print(f"")
                    print(f"  Key frequency across elements:")
                    print(f"  {'Key':<30} {'Count':<10} {'%'}")
                    print(f"  {'-'*30} {'-'*10} {'-'*8}")
                    for key, count in key_counter.most_common(30):
                        pct = f"{count/len(data)*100:.1f}%"
                        print(f"  {key:<30} {count:<10} {pct}")
            print(f"")

        # If root is object, show key summary
        elif isinstance(data, dict):
            print(f"## Object Summary")
            print(f"")
            print(f"  Total keys: {len(data)}")
            print(f"")
            print(f"  {'Key':<30} {'Type':<15} {'Size/Value'}")
            print(f"  {'-'*30} {'-'*15} {'-'*20}")
            for k, v in list(data.items())[:30]:
                vtype = type(v).__name__
                if isinstance(v, list):
                    size = f"[{len(v)} items]"
                elif isinstance(v, dict):
                    size = f"{{{len(v)} keys}}"
                elif isinstance(v, str):
                    size = f'"{v[:20]}"'
                else:
                    size = str(v)[:20]
                print(f"  {k:<30} {vtype:<15} {size}")
            print(f"")

except json.JSONDecodeError as e:
    print(f"  ERROR: Invalid JSON — {e}")
    sys.exit(1)
except Exception as e:
    print(f"  ERROR: {e}")
    sys.exit(1)
PYJSON

else
  echo "ERROR: Unsupported file type '.$FILE_EXT'. Supports: .csv, .tsv, .json, .jsonl" >&2
  exit 2
fi

echo "=============================================="
echo " Profile complete"
echo "=============================================="
exit 0
