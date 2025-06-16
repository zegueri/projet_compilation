#!/bin/sh
set -e
repo_dir="$(dirname "$0")/.."
cd "$repo_dir"
make >/dev/null
ret=0
for t in tests/*.txt; do
    base=$(basename "$t" .txt)
    echo "-- $base --"
    ./logic_interpreter < "$t" > "tests/$base.out" 2>&1 || true
    if diff -u "tests/$base.exp" "tests/$base.out"; then
        echo "PASS"
    else
        echo "FAIL"
        ret=1
    fi
    rm "tests/$base.out"
    echo
done
exit $ret
