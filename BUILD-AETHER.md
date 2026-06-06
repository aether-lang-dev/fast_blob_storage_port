# Aether port — build & test

fbs-core is being ported Go → Aether, leaf-first, replace-in-place. See
`~/.claude/plans/fizzy-jingling-badger.md` for the full plan and
`docs/` for the original Go architecture.

## Layout

```
lib/crypto/hmac.ae          # HMAC-SHA256 (RFC 2104; std has no HMAC)
lib/urlescape/urlescape.ae  # Go url.PathEscape equivalent (no URL codec in std)
internal/<pkg>/<pkg>.ae  # ported packages (mirror internal/<pkg>/)
aethertests/**/ *_test.ae   # aeocha test suites (one per module)
scripts/aetest.sh           # test runner
```

The repo is Aether-only (the Go tree was removed once the port reached parity).
still-building Go tree during replace-in-place. A Go file is deleted
only once its Aether replacement AND all its Go importers are ported, so
`go build ./...` / `go test ./...` stay green throughout.

**Module naming:** the module file is named after the import name, e.g.
`internal/responses/responses.ae` (imported as `import responses`),
`internal/s3compat/region.ae` (`import region`). The test runner
symlinks every `lib/**` and `internal/**` `.ae` into a flat lib root
by basename, so basenames must be unique across the port.

## Running tests

```sh
scripts/aetest.sh                                   # all suites
scripts/aetest.sh aethertests/internal/publicread/signer_test.ae   # one
```

The runner assembles `.ae_test_lib/` (gitignored) of symlinks —
vendored `aeocha.ae` plus every ported module — and runs each test with
`AETHER_LIB_DIR=.ae_test_lib ae run`. **Module resolution keys on
`AETHER_LIB_DIR` / `--lib`, NOT `AETHER_INCLUDE_PATH`** (that var is
ignored; debug with `ae lib-path`).

## Toolchain facts (verified)

- **MD5**: `cryptography.hash_hex("md5", data, len)` — no custom C needed.
- **HMAC-SHA256**: hand-rolled in `lib/crypto/hmac.ae` (std excludes it).
- **base64**: `cryptography.base64_encode_padded(data, len)`.
- **SQLite** (for metadata, next): `import contrib.sqlite`, build with
  `aether.toml` `extra_sources=[".../aether_sqlite.c"]` +
  `[build] link_flags = "-lsqlite3"`. Verified working.
- **HTTP**: in-process test = `server_create(0)` → `server_set_host` →
  register routes → `http_server_start_background_raw` → `sleep(200)` →
  `http_server_port` → drive with `std.http.client` v2. Timeouts are a
  typed `Duration` (`3s`, not a raw ns int).
- aeocha `expect_http_header` is a no-op stub — verify headers with
  `client.response_header(resp, name)` + `assert_str_eq` instead.

## Parity discipline

Crypto/encoding ports assert **byte-identical** output against the Go
reference, not just internal consistency. E.g. `signer_test.ae` asserts
`sign_path(...)` == the hex emitted by `go run` of the real
`internal/publicread` (`bd8bb140...`). When porting auth/checksums,
generate the Go reference value first (a throwaway `main.go` inside the
package dir so the `internal/` import is allowed) and assert against it.

## Status

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
