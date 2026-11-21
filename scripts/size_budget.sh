#!/bin/sh
# Fail when the shipped QuietCast/ tree grows past the budget passed as $1.
set -eu

budget=${1:?size budget in bytes required}
bytes=$(find QuietCast -type f -printf '%s\n' | awk '{ sum += $1 } END { print sum + 0 }')
echo "QuietCast/ is ${bytes} bytes (budget ${budget})"
if [ "$bytes" -gt "$budget" ]; then
    echo "Shipped files grew past the budget." >&2
    exit 1
fi
