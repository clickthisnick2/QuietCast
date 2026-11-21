#!/bin/sh
# Fail when QuietCastLogic line coverage is below the floor passed as $1.
set -eu

floor=${1:?coverage floor percent required}
bin=$(swift build --show-bin-path)
object="$bin/QuietCastLogic.o"
profile="$bin/codecov/default.profdata"

if [ ! -f "$profile" ]; then
    echo "No coverage profile at $profile. Run 'swift test --enable-code-coverage' first." >&2
    exit 1
fi

report=$(llvm-cov report "$object" -instr-profile="$profile")
printf '%s\n' "$report"
percent=$(printf '%s\n' "$report" | awk '/^TOTAL/ { gsub(/%/, "", $10); print $10; found=1 } END { if (!found) exit 1 }')
echo "line coverage ${percent}% (floor ${floor}%)"
awk -v percent="$percent" -v floor="$floor" 'BEGIN { if (percent + 0 < floor + 0) exit 1 }'
