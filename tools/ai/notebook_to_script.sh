#!/bin/bash
set -euo pipefail

###############################################################################
# notebook_to_script.sh — Convert Jupyter .ipynb to clean .py script
# Usage: notebook_to_script.sh <notebook.ipynb> [output.py]
# Exit codes: 0=OK, 1=issues found, 2=error
###############################################################################

if [[ $# -lt 1 ]]; then
  cat <<EOF
Usage: $(basename "$0") <notebook.ipynb> [output.py]

  notebook.ipynb  Path to the Jupyter notebook
  output.py       Output Python script path (default: same name with .py extension)

Options:
  --no-markdown   Skip markdown cell conversion to comments
  --no-outputs    Skip output comments (default: outputs are excluded)
  --keep-magic    Keep Jupyter magic commands (%%time, !pip, etc.)

Examples:
  $(basename "$0") analysis.ipynb
  $(basename "$0") model/train.ipynb model/train_script.py
EOF
  exit 2
fi

# --- Parse arguments ---
NOTEBOOK=""
OUTPUT=""
INCLUDE_MARKDOWN=true
KEEP_MAGIC=false

for arg in "$@"; do
  case "$arg" in
    --no-markdown)  INCLUDE_MARKDOWN=false ;;
    --keep-magic)   KEEP_MAGIC=true ;;
    --no-outputs)   ;; # outputs excluded by default
    --help|-h)
      exec "$0"  # Re-run with no args to show usage
      ;;
    *)
      if [[ -z "$NOTEBOOK" ]]; then
        NOTEBOOK="$arg"
      elif [[ -z "$OUTPUT" ]]; then
        OUTPUT="$arg"
      fi
      ;;
  esac
done

if [[ -z "$NOTEBOOK" ]]; then
  echo "ERROR: Notebook path is required." >&2
  exit 2
fi

if [[ ! -f "$NOTEBOOK" ]]; then
  echo "ERROR: File '$NOTEBOOK' not found." >&2
  exit 2
fi

# Default output path
if [[ -z "$OUTPUT" ]]; then
  OUTPUT="${NOTEBOOK%.ipynb}.py"
fi

echo "=============================================="
echo " Notebook to Script Converter"
echo " Input:  $NOTEBOOK"
echo " Output: $OUTPUT"
echo "=============================================="
echo ""

# --- Convert using Python ---
PYTHON_CMD="python3"
if ! command -v python3 &>/dev/null; then
  PYTHON_CMD="python"
fi

"$PYTHON_CMD" - "$NOTEBOOK" "$OUTPUT" "$INCLUDE_MARKDOWN" "$KEEP_MAGIC" <<'PYCONVERT'
import sys
import json

notebook_path = sys.argv[1]
output_path = sys.argv[2]
include_markdown = sys.argv[3] == "true"
keep_magic = sys.argv[4] == "true"

try:
    with open(notebook_path, 'r', encoding='utf-8') as f:
        nb = json.load(f)
except json.JSONDecodeError as e:
    print(f"  ERROR: Invalid notebook JSON — {e}")
    sys.exit(2)
except Exception as e:
    print(f"  ERROR: Cannot read notebook — {e}")
    sys.exit(2)

# Validate notebook structure
if 'cells' not in nb:
    print("  ERROR: Not a valid Jupyter notebook (missing 'cells')")
    sys.exit(2)

cells = nb['cells']

# Detect kernel/language
kernel_info = nb.get('metadata', {}).get('kernelspec', {})
language = kernel_info.get('language', 'python')
display_name = kernel_info.get('display_name', 'Python')

lines = []

# Header
lines.append(f"#!/usr/bin/env {language}")
lines.append(f'"""')
lines.append(f"Converted from: {notebook_path}")
lines.append(f"Kernel: {display_name}")
lines.append(f'"""')
lines.append("")

code_cells = 0
markdown_cells = 0
skipped_magic = 0
total_lines = 0

for i, cell in enumerate(cells):
    cell_type = cell.get('cell_type', '')
    source = cell.get('source', [])

    # Handle source as list or string
    if isinstance(source, list):
        source_text = ''.join(source)
    else:
        source_text = source

    source_lines = source_text.rstrip('\n').split('\n')

    if cell_type == 'markdown' and include_markdown:
        markdown_cells += 1
        lines.append("")
        lines.append(f"# {'=' * 70}")

        for line in source_lines:
            # Convert markdown headers to comment headers
            if line.startswith('#'):
                lines.append(f"# {line}")
            else:
                lines.append(f"# {line}")

        lines.append(f"# {'=' * 70}")
        lines.append("")

    elif cell_type == 'code':
        code_cells += 1

        # Add cell separator comment
        lines.append(f"# --- Cell [{i+1}] ---")
        lines.append("")

        for line in source_lines:
            stripped = line.strip()

            # Handle magic commands
            if stripped.startswith('%') or stripped.startswith('!'):
                if keep_magic:
                    lines.append(f"# MAGIC: {line}")
                else:
                    skipped_magic += 1
                    lines.append(f"# [magic] {line}")
                continue

            # Handle IPython display calls that won't work in script
            if stripped.startswith('display(') or stripped == 'df' or stripped == 'df.head()':
                lines.append(f"print({stripped})" if stripped not in ('df', 'df.head()') else f"print({stripped})")
                total_lines += 1
                continue

            lines.append(line)
            total_lines += 1

        lines.append("")

    elif cell_type == 'raw':
        lines.append("")
        lines.append(f"# --- Raw Cell [{i+1}] ---")
        for line in source_lines:
            lines.append(f"# {line}")
        lines.append("")

# Write output
output_text = '\n'.join(lines) + '\n'

with open(output_path, 'w', encoding='utf-8') as f:
    f.write(output_text)

print(f"  Conversion Summary:")
print(f"    Total cells:      {len(cells)}")
print(f"    Code cells:       {code_cells}")
print(f"    Markdown cells:   {markdown_cells}")
print(f"    Code lines:       {total_lines}")
print(f"    Magic commands:   {skipped_magic} (commented out)")
print(f"")
print(f"  Output written to: {output_path}")
PYCONVERT

echo ""
echo "=============================================="
echo " Conversion complete"
echo "=============================================="
exit 0
