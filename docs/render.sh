#!/usr/bin/env bash
# Renders every .d2 diagram in this folder to the .svg beside it.
set -euo pipefail

cd "$(dirname "$0")"

for diagram in *.d2; do
  svg="${diagram%.d2}.svg"
  d2 -t 201 "$diagram"
  if grep -q foreignObject "$svg"; then
    echo "$svg holds a foreignObject, which most viewers draw as an empty box." >&2
    echo "Replace the |md block in $diagram with a plain quoted label." >&2
    exit 1
  fi
done
