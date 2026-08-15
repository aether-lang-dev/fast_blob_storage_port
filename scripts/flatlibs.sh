#!/bin/sh
# flatlibs.sh — (re)build the flat module root used for module resolution.
#
# fbs-core imports its own modules by BARE BASENAME (`import s3server`,
# `import schema`) while the files live one-per-package under internal/
# and lib/. Aether resolves those names against the `--lib` search path,
# and that path is capped at **8 entries** — fewer than this repo has
# package dirs, and the compiler drops the overflow with only a warning
# ("--lib search path is full"), so the build fails far downstream with
# a confusing "module X has no export Y".
#
# So instead of N directories we hand it ONE: a flat root of symlinks,
# every module addressed by basename. Because it is flat and takes
# precedence, a module basename must not collide with a std submodule
# that std itself imports (that clash is why lib/crypto/hmac.ae had to
# become ctcompare.ae — it was shadowing std.cryptography.hmac).
#
# Usage: scripts/flatlibs.sh [dest]      (default: target/.libroot)
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-$ROOT/target/.libroot}"

rm -rf "$DEST"
mkdir -p "$DEST"

for f in $(find "$ROOT/lib" "$ROOT/internal" -name '*.ae' 2>/dev/null); do
    base="$(basename "$f")"
    case "$base" in .*) continue ;; esac   # skip .build.ae and friends
    if [ -e "$DEST/$base" ]; then
        echo "flatlibs: DUPLICATE basename '$base' ($f) — module names must be unique" >&2
        exit 1
    fi
    ln -sf "$f" "$DEST/$base"
done
