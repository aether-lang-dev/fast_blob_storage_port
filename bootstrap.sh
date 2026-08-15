#!/usr/bin/env bash
# One-command bootstrap for fbs-core.
#
# Ensures the Aether toolchain (`ae`) and the build runner (`aeb`) are present
# and recent enough, then builds the server and runs the test suite. Mirrors
# aether-ui/bootstrap.sh.
#
# Toolchains install via their canonical remote installers (work from a bare
# clone, install released builds to a user prefix):
#     aether: https://raw.githubusercontent.com/aether-lang-org/aether/main/get.sh
#     aeb:    https://raw.githubusercontent.com/aether-lang-org/aeb/main/install.sh
#
# Idempotent: a no-op for the toolchain when `ae`/`aeb` are already good.
#
# The floors come from the AETHER_PIN / AEB_PIN files next to this script, so
# the pin lives in ONE place and this script never drifts from it.
#
# Env overrides:
#   PREFIX        install prefix                 (default: $HOME/.local; no sudo)
#   AETHER_REF    ae tag/branch/SHA to install   (default: the AETHER_PIN tag)
#   AEB_REF       aeb tag/branch/SHA to install  (default: latest tag)
#   MIN_AE        minimum acceptable ae version  (default: read from AETHER_PIN)
# Extra args pass through to scripts/aetest.sh (e.g. ./bootstrap.sh one_test.ae).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"; export PREFIX
AETHER_GET_URL="https://raw.githubusercontent.com/aether-lang-org/aether/main/get.sh"
AEB_INSTALL_URL="https://raw.githubusercontent.com/aether-lang-org/aeb/main/install.sh"

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; }
ae_version() { ae --version 2>/dev/null | head -n1 | sed -E 's/^ae ([0-9]+\.[0-9]+\.[0-9]+).*/\1/'; }

# read_pin FILE : the one bare version string in a pin file (skip # comments).
read_pin() { grep -vE '^\s*(#|$)' "$1" | head -n1 | tr -d '[:space:]'; }

PIN_AE="$(read_pin "$HERE/AETHER_PIN")"
MIN_AE="${MIN_AE:-$PIN_AE}"

# fetch_run URL : download an installer to a temp file and run it under sh,
# inheriting the (exported) env the caller set. Downloads first, then runs the
# saved file, so a fetch failure can't be masked the way piping curl into a
# shell would.
fetch_run() {
    command -v curl >/dev/null 2>&1 || die "curl is required to install the Aether toolchain (or install ae/aeb yourself and re-run)."
    local tmp rc; tmp="$(mktemp)"
    if curl -fsSL "$1" -o "$tmp"; then sh "$tmp"; rc=$?; else rc=$?; fi
    rm -f "$tmp"; return $rc
}

export PATH="$PREFIX/bin:$PATH"   # so freshly-installed ae/aeb are found below

# ---- 1. Aether toolchain (ae) ----
if command -v ae >/dev/null 2>&1 && have="$(ae_version || true)" && [ -n "$have" ] && version_ge "$have" "$MIN_AE"; then
    say "ae $have already on PATH (>= $MIN_AE) — skipping"
else
    say "installing ae via get.sh (AETHER_REF=${AETHER_REF:-v$PIN_AE}, PREFIX=$PREFIX)"
    AETHER_REF="${AETHER_REF:-v$PIN_AE}" fetch_run "$AETHER_GET_URL" || die "ae install failed (get.sh)."
    command -v ae >/dev/null 2>&1 || die "ae installed but not on PATH — ensure $PREFIX/bin is on PATH."
    have="$(ae_version || true)"
    version_ge "$have" "$MIN_AE" || die "ae $have is older than the AETHER_PIN floor $MIN_AE."
    say "ae $have ready"
fi

# ---- 2. Build runner (aeb) ----
if command -v aeb >/dev/null 2>&1; then
    say "aeb already on PATH — skipping"
else
    say "installing aeb via install.sh (AEB_REF=${AEB_REF:-latest}, PREFIX=$PREFIX)"
    AEB_REF="${AEB_REF:-}" AETHER="$(command -v ae)" fetch_run "$AEB_INSTALL_URL" || die "aeb install failed (install.sh)."
    command -v aeb >/dev/null 2>&1 || die "aeb installed but not on PATH — ensure $PREFIX/bin is on PATH."
fi
say "using aeb: $(command -v aeb)"

# ---- 3. Test the project ----
# The suite is the real gate here (it exercises every ported module); the
# server binary is built by `aeb` from cmd/.build.ae.
case ":$PATH:" in *":$PREFIX/bin:"*) : ;; *) say "tip: add '$PREFIX/bin' to your shell PATH permanently";; esac
cd "$HERE"
say "running test suite"
./scripts/aetest.sh "$@" || die "test suite failed."
say "done."
