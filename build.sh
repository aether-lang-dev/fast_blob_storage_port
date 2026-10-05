#!/usr/bin/env bash
# build.sh — build the fbs-core server binary via aeb.
#
# Regenerates the flat module root first (cmd/.build.ae points `lib()` at
# it, and its symlinks are absolute to this checkout, so it is generated
# rather than committed), builds contrib.sqlite's veneer archive into
# target/contrib (a release toolchain doesn't ship it), then runs aeb.
#
# Use ./bootstrap.sh instead if you also need the toolchain installed.
#
# Extra args pass through to aeb (e.g. ./build.sh --list).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

command -v aeb >/dev/null 2>&1 || {
    echo "error: aeb not on PATH — run ./bootstrap.sh first." >&2; exit 1; }

./scripts/flatlibs.sh
./scripts/sqlite_veneer.sh >/dev/null   # contrib.sqlite's -laether_sqlite

if [ "$#" -gt 0 ]; then
    exec aeb "$@"
fi

aeb cmd/.build.ae
echo "built: target/build/cmd/bin/program"
