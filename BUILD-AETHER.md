# Aether port — build & test

fbs-core is being ported Go → Aether, leaf-first, replace-in-place. See
`~/.claude/plans/fizzy-jingling-badger.md` for the full plan and
`docs/` for the original Go architecture.

## Layout

```
lib/crypto/ctcompare.ae     # constant-time hex compare (std has no timing-safe ==)
lib/crypto/sigv4.ae         # AWS SigV4 signing (on std.cryptography)
internal/<pkg>/<pkg>.ae     # ported packages (mirror internal/<pkg>/)
aethertests/**/ *_test.ae   # std.spec test suites (one per module)
scripts/aetest.sh           # test runner
scripts/flatlibs.sh         # generates the flat module root the build resolves against
scripts/sqlite_veneer.sh    # builds contrib.sqlite's -laether_sqlite archive into target/contrib
build.sh / bootstrap.sh     # build / install-toolchain-then-test
AETHER_PIN / AEB_PIN        # toolchain version floors
```

The repo is Aether-only (the Go tree was removed once the port reached parity).
still-building Go tree during replace-in-place. A Go file is deleted
only once its Aether replacement AND all its Go importers are ported, so
`go build ./...` / `go test ./...` stay green throughout.

**Module naming:** the module file is named after the import name, e.g.
`internal/responses/responses.ae` (imported as `import responses`),
`internal/s3compat/region.ae` (`import region`). Both the test runner and
the build flatten every `lib/**` and `internal/**` `.ae` into a lib root
by basename, so basenames must be unique across the port — **and must not
collide with a std submodule that std itself imports.** That second rule
is not theoretical: `lib/crypto/hmac.ae` shadowed `std.cryptography.hmac`
(which `std.cryptography` delegates `hmac_sha256_hex` to as of 0.542), so
every caller died with "'hmac_sha256_hex' is not exported from module
'hmac'". It is now `ctcompare.ae`.

## Building

```sh
./bootstrap.sh     # install ae + aeb to the pinned floors, then run the suite
./build.sh         # build the server binary -> target/build/cmd/bin/program
```

`build.sh` regenerates `target/.libroot` (via `scripts/flatlibs.sh`) and
runs `aeb cmd/.build.ae`. That flat root exists because **`--lib` accepts
at most 8 entries**: this repo has more package dirs than that, and the
compiler drops the overflow with only a warning, so listing dirs
individually fails far downstream with a confusing "module X has no
export Y". One generated dir sidesteps the cap entirely.

`cmd/.build.ae` also carries `-lnghttp2` (plus `-L/opt/homebrew/lib` for
macOS) alongside `-lsqlite3`: opting into aeb's manual-link path (via
`link_flag`) means the toolchain's own link line is not inherited — aeb
resolves zlib/openssl/pcre2 itself but not nghttp2 — and the shipped
`libaether.a` is built with HTTP/2.

`contrib.sqlite` declares `@link("-laether_sqlite -lsqlite3 -lm")`. A source
install's `make contrib` builds that veneer archive; a **release** install
(get.sh — the preferred route) ships the contrib source but not the archive,
so `build.sh` first runs `scripts/sqlite_veneer.sh`, which compiles the
toolchain's own `contrib/sqlite/aether_sqlite.c` into `target/contrib/`
(rebuilt when the toolchain's copy changes); `cmd/.build.ae` puts that on
`-L` via `${root}`. No sibling `aether` checkout is needed any more.

## Running tests

```sh
scripts/aetest.sh                                   # all suites
scripts/aetest.sh aethertests/internal/publicread/signer_test.ae   # one
```

The runner assembles `.ae_test_lib/` (gitignored) of symlinks over every
ported module and runs each test with `AETHER_LIB_DIR=.ae_test_lib ae
run`. The framework needs no wiring — `std.spec` ships with the
toolchain. **Module resolution keys on `AETHER_LIB_DIR` / `--lib`, NOT
`AETHER_INCLUDE_PATH`** (that var is ignored; debug with `ae lib-path`).

Tests that link SQLite go through `scripts/aetest_sqlite.sh` (they can't
use `ae run`, which can't pass link flags); `aetest.sh` routes them
automatically. It uses the same `target/contrib` veneer archive as the
build. Both runners clear the ae build cache first (`$AETHER_CACHE_DIR`,
default `~/.aether/cache`).

Each suite ends `return spec.run_summary(fw)`: since Aether 0.612
`run_summary` returns its verdict instead of exiting, so a bare call makes a
failing suite exit 0 (measured) and the runners would report green.

## Toolchain facts (verified)

- **Byte payloads are `byte[]` slices** (Aether 0.758, #2301): std calls
  that take bytes (`fs.write_atomic`, `fs.pwrite`, `cryptography.*_hex`,
  `hmac_sha256_*`, `digest_update`, client `set_body`, ...) take one slice,
  not `(data, len)`. For a string use `string.bytes(s)`; for an owned
  length-preserving string with a known length, `string.bytes(s)[0..n]`.
  `http.request_body` returns a RAW `char*` that may hold NULs, which
  `string.bytes` would strlen short — bound the bare pointer instead:
  `(string.aether_string_raw_ptr(p) as byte[])[0..n]` (storage's `_view`).
- **MD5**: `cryptography.md5_hex(bytes)` / `hash_hex("md5", bytes)` — no
  custom C needed.
- **HMAC-SHA256**: `cryptography.hmac_sha256_hex` / `_bytes` (std ships it;
  the old hand-rolled copy is gone).
- **base64**: `encoding.base64_encode_padded(bytes)` (std.encoding).
- **SQLite**: `import contrib.sqlite` (resolves from a release install since
  0.741); link needs `-laether_sqlite` (see `scripts/sqlite_veneer.sh`) +
  `-lsqlite3`.
- **HTTP**: in-process test = `server_create(0)` → `server_set_host` →
  register routes → `http_server_start_background_raw` → `sleep(200)` →
  `http_server_port` → drive with `std.http.client` v2. Timeouts are a
  typed `Duration` (`3s`, not a raw ns int).
- `httptest.expect_http_header` is now a real matcher (it was a no-op stub in
  aeocha), but the existing tests verify headers with
  `client.response_header(resp, name)` + `assert_str_eq`, which is equally
  valid and asserts exact equality.

## Parity discipline

Crypto/encoding ports assert **byte-identical** output against the Go
reference, not just internal consistency. E.g. `signer_test.ae` asserts
`sign_path(...)` == the hex emitted by `go run` of the real
`internal/publicread` (`bd8bb140...`). When porting auth/checksums,
generate the Go reference value first (a throwaway `main.go` inside the
package dir so the `internal/` import is allowed) and assert against it.

## Status

**Aether-only + modernized onto std (ae 0.778.0 + aeb v0.325; was 0.542.0
— see AETHER_PIN for what the upgrade changed).** The Go tree is gone;
the repo leans on stdlib that landed in response to its own asks. Notable:
- Randomness from std.cryptography CSPRNG + std.uuid (no clock-seeded PRNG).
- HMAC/MD5/SigV4 on std.cryptography; lib/crypto/ctcompare is just equal_hex.
- Lexical paths via std.fs.clean/is_within_base; URL via std.url; XML via
  std.xml; JSON responses via std.json (incl. json.from_int for metrics).
- Per-server state via std.http user_data (no C shim — repo is 0 hand C).
- GET via http.serve_file (sendfile); PUT streams via request_body_read.
- object_get returns (Object, err) (struct-in-tuple works since #634/#752).

Idle RSS ~7.5 MB. Both hot-path sides (up/download) are now RAM-bounded.

### Original port status


**Migration complete.** The repo is Aether-only — the Go tree (93 files,
go.mod/go.sum) was removed once the port reached parity. Ported: storage,
metadata (6 repos), auth (bearer + SigV4), s3 (full object lifecycle,
multipart, copy, bulk delete, listing), setup/management API, startup
reconcile, and the `cmd/main.ae` binary. The built `fbs-server` serves
real S3 + management traffic (verified via curl). Crypto/encoding paths
(HMAC, SigV4, url-escape, multipart ETag, signatures) are asserted
byte-identical to the original Go.

Deferred / not ported (optional or not exercised by tests): the metadata
LRU cache (Go gated it behind a config flag), SigV4 *request* auth wiring
on the live server (the SigV4 crypto is proven and bearer covers the
tested path), per-request checksum (Content-MD5) validation, CORS
middleware, and the management bucket/key/activity *list* endpoints
(metrics is wired). These can layer onto the existing foundation.
