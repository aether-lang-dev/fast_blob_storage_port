#!/bin/sh
# aetest.sh — run the Aether-port std.spec test suite.
#
# Module resolution in Aether keys on AETHER_LIB_DIR (NOT
# AETHER_INCLUDE_PATH — that var is ignored). We assemble a single flat
# lib root (.ae_test_lib/) of symlinks over every ported lib/*/*.ae and
# internal/*/*.ae module, addressed by bare basename so `import signer`
# / `import ctcompare` etc. resolve. Then run each
# aethertests/**/ *_test.ae through `ae run`.
#
# The framework itself needs NO wiring: aeocha was absorbed into the
# stdlib as std.spec (+ std.http.client.httptest), so it resolves from
# the toolchain like any other std module.
#
# CAUTION: this root is FLAT and outranks std's own submodules, so a
# module here must not share a basename with one std imports internally
# (that clash is why lib/crypto/hmac.ae is now ctcompare.ae).
#
# Usage:
#   scripts/aetest.sh                 # run all *_test.ae
#   scripts/aetest.sh path/to/x_test.ae   # run one
#
# Exit 0 only if every test exits 0.

set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIBDIR="$ROOT/.ae_test_lib"

# The ae build cache keys on the symlink's mtime, not its target's, so
# edits to a real module behind a symlinked lib entry are missed. Clear
# the cache each run so symlinked-lib edits always take effect.
rm -rf "$HOME/.aether/cache" 2>/dev/null || true

rm -rf "$LIBDIR"
mkdir -p "$LIBDIR"

# Flatten every ported module to <basename>.ae in the lib root.
for f in $(find "$ROOT/lib" "$ROOT/internal" -name '*.ae' 2>/dev/null); do
    ln -sf "$f" "$LIBDIR/$(basename "$f")"
done

run_one() {
    t="$1"
    printf '\n=== %s ===\n' "${t#$ROOT/}"
    if ! AETHER_LIB_DIR="$LIBDIR" ae run "$t"; then
        echo "FAIL: $t"
        return 1
    fi
}

rc=0
if [ -n "$1" ]; then
    run_one "$ROOT/$1" || rc=1
else
    # A test needs the sqlite build+link runner if it imports contrib.sqlite
    # (directly or transitively via schema/repos/s3server). Detect by grep.
    for t in $(find "$ROOT/aethertests" -name '*_test.ae' | sort); do
        rel="${t#$ROOT/}"
        if grep -qE 'import (schema|s3server|contrib\.sqlite|buckets|objects|users|multipart|activity|management)\b' "$t"; then
            if ! "$ROOT/scripts/aetest_sqlite.sh" "$rel"; then rc=1; fi
        else
            run_one "$t" || rc=1
        fi
    done
fi

if [ "$rc" -eq 0 ]; then
    echo ""
    echo "ALL AETHER TESTS PASSED"
fi
exit "$rc"
