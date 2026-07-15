#!/usr/bin/env bash
# Merges several static libraries (.a) into a single static library.
#
# Usage: merge_static_libs.sh <AR> <temp-folder> <output.a> <lib1.a> <lib2.a> ...
#
# Each archive is extracted into its own numbered subfolder (not all into
# the same folder) to avoid .o files with the same name coming from
# different libraries (e.g. "Store.cpp.o" present in both ToolFrameworkCore
# and ToolDAQFramework) from overwriting each other.

set -euo pipefail

AR="$1"; shift
OUTDIR="$1"; shift
OUTPUT="$1"; shift
ARCHIVES=("$@")

rm -rf "$OUTDIR"
mkdir -p "$OUTDIR"

i=0
for a in "${ARCHIVES[@]}"; do
    i=$((i + 1))
    d="$OUTDIR/lib_${i}"
    mkdir -p "$d"
    (cd "$d" && "$AR" x "$a")
done

rm -f "$OUTPUT"
mkdir -p "$(dirname "$OUTPUT")"

# find + xargs instead of a plain *.o glob: correctly handles the case
# where there are many .o files (command line length limit).
find "$OUTDIR" -name '*.o' -print0 | xargs -0 "$AR" rcs "$OUTPUT"

echo "[merge_static_libs] Created $OUTPUT from ${#ARCHIVES[@]} static libraries"
