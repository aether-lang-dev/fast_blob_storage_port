#!/bin/sh
# sqlite_veneer.sh — build contrib.sqlite's veneer archive into the repo.
#
# contrib.sqlite declares `@link("-laether_sqlite -lsqlite3 -lm")`, so every
# program importing it links against libaether_sqlite.a — the veneer archive a
# SOURCE install's `make contrib` builds under <lib_dir>/contrib. A RELEASE
# install (get.sh / `ae install`, the preferred toolchain route) ships the
# contrib *source* (since 0.741.0) but not that archive, so the link dies with
# "library 'aether_sqlite' not found". We compile the veneer ourselves from the
# toolchain's own shipped aether_sqlite.c (same version as the compiler) into
# target/contrib/, which cmd/.build.ae and scripts/aetest_sqlite.sh put on -L.
# Links the system libsqlite3 (needs its headers: libsqlite3-dev on Linux).
#
# Contrib source is looked up in: $AETHER_CONTRIB, the release layout next to
# `ae` (<prefix>/share/aether/contrib), then a source checkout at
# $AETHER_REPO/contrib.
#
# Usage: scripts/sqlite_veneer.sh [dest-dir]   (default: target/contrib)
# Prints the dest dir on success.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-$ROOT/target/contrib}"

find_contrib() {
    for c in "${AETHER_CONTRIB:-}" \
             "$(dirname "$(command -v ae 2>/dev/null || echo /nonexistent/x)")/../share/aether/contrib" \
             "${AETHER_REPO:-}/contrib"; do
        if [ -n "$c" ] && [ -f "$c/sqlite/aether_sqlite.c" ]; then
            (cd "$c" && pwd); return 0
        fi
    done
    return 1
}

CONTRIB="$(find_contrib)" || {
    echo "sqlite_veneer: can't find contrib/sqlite/aether_sqlite.c (set AETHER_CONTRIB)" >&2; exit 1; }
SRC="$CONTRIB/sqlite/aether_sqlite.c"
LIB="$DEST/libaether_sqlite.a"

mkdir -p "$DEST"
# Rebuild when missing or when the toolchain's source differs from the copy we
# last built from (a toolchain switch; mtimes from a tarball can't be trusted).
STAMP="$DEST/aether_sqlite.c.built"
if [ ! -f "$LIB" ] || ! cmp -s "$SRC" "$STAMP"; then
    ${CC:-cc} -O2 -fPIC -c "$SRC" -o "$DEST/aether_sqlite.o"
    rm -f "$LIB"
    ar rcs "$LIB" "$DEST/aether_sqlite.o"
    rm -f "$DEST/aether_sqlite.o"
    cp "$SRC" "$STAMP"
fi
echo "$DEST"
