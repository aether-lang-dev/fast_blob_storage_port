#!/bin/sh
# aetest_sqlite.sh — run an aeocha test that needs contrib.sqlite.
#
# SQLite-linked tests can't use `ae run` (it can't pass -lsqlite3). They
# need `ae build` with an aether.toml carrying extra_sources +
# link_flags, then execution of the built binary. This runner stages a
# work dir per test: symlinks the flat lib root (aeocha + ported
# modules) AND the aether contrib/ dir (so `import contrib.sqlite`
# resolves), writes the toml, builds, runs.
#
# Usage: scripts/aetest_sqlite.sh aethertests/internal/metadata/x_test.ae

set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AEOCHA="${AEOCHA_REPO:-/home/paul/scm/aeocha}"
AETHER="${AETHER_REPO:-/home/paul/scm/aether}"
LIBDIR="$ROOT/.ae_test_lib"

if [ -z "$1" ]; then echo "usage: $0 <test.ae>"; exit 2; fi
TEST="$ROOT/$1"

# Skip if libsqlite3 absent.
if ! pkg-config --exists sqlite3 2>/dev/null; then
    if ! gcc -lsqlite3 -xc /dev/null -o /dev/null 2>/dev/null; then
        echo "  [SKIP] $1: libsqlite3 not installed"; exit 0
    fi
fi

rm -rf "$HOME/.aether/cache" 2>/dev/null || true

# (Re)build the flat lib root of symlinks.
rm -rf "$LIBDIR"; mkdir -p "$LIBDIR"
ln -sf "$AEOCHA/aeocha.ae" "$LIBDIR/aeocha.ae"
for f in $(find "$ROOT/lib" "$ROOT/internal" -name '*.ae' 2>/dev/null); do
    ln -sf "$f" "$LIBDIR/$(basename "$f")"
done

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
ln -s "$AETHER/contrib" "$WORK/contrib"
cp "$TEST" "$WORK/probe.ae"

# Server integration tests also need the appstate.c global-handle source.
APPSTATE="$ROOT/internal/s3/appstate.c"
EXTRA_APPSTATE=""
if grep -q 'appstate_' "$TEST" 2>/dev/null || grep -lq 'appstate_' "$ROOT/internal/s3/"*.ae 2>/dev/null; then
    cp "$APPSTATE" "$WORK/appstate.c"
    EXTRA_APPSTATE=', "appstate.c"'
fi

cat > "$WORK/aether.toml" <<EOF
[project]
name = "metadata_probe"
version = "0.0.0"

[[bin]]
name = "probe"
path = "probe.ae"
extra_sources = ["contrib/sqlite/aether_sqlite.c"${EXTRA_APPSTATE}]

[build]
link_flags = "-lsqlite3"
EOF

printf '\n=== %s ===\n' "$1"
if ! ( cd "$WORK" && AETHER_LIB_DIR="$LIBDIR" ae build probe.ae -o "$WORK/probe" >"$WORK/build.log" 2>&1 ); then
    echo "  [FAIL] build:"; sed 's/^/    /' "$WORK/build.log" | head -40; exit 1
fi
if [ ! -x "$WORK/probe" ]; then
    echo "  [FAIL] no binary produced:"; sed 's/^/    /' "$WORK/build.log" | head -40; exit 1
fi
AETHER_LIB_DIR="$LIBDIR" "$WORK/probe"
