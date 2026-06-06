# Aether port — build & test

fbs-core is being ported Go → Aether, leaf-first, replace-in-place. See
`~/.claude/plans/fizzy-jingling-badger.md` for the full plan and
`docs/` for the original Go architecture.

## Layout

```
lib/crypto/hmac.ae          # HMAC-SHA256 (RFC 2104; std has no HMAC)
lib/urlescape/urlescape.ae  # Go url.PathEscape equivalent (no URL codec in std)
internal_ae/<pkg>/<pkg>.ae  # ported packages (mirror internal/<pkg>/)
aethertests/**/ *_test.ae   # aeocha test suites (one per module)
scripts/aetest.sh           # test runner
```

`internal_ae/` (not `internal/`) keeps the Aether port isolated from the
still-building Go tree during replace-in-place. A Go file is deleted
only once its Aether replacement AND all its Go importers are ported, so
`go build ./...` / `go test ./...` stay green throughout.

**Module naming:** the module file is named after the import name, e.g.
`internal_ae/responses/responses.ae` (imported as `import responses`),
`internal_ae/s3compat/region.ae` (`import region`). The test runner
symlinks every `lib/**` and `internal_ae/**` `.ae` into a flat lib root
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

Done: s3compat, responses, publicread, lib/crypto/hmac, lib/urlescape.
Next (topological order): storage (std.fs) → metadata (contrib.sqlite) →
auth (hmac+md5+sha256) → objectops/http-middleware/config → s3 handlers
(std.http server + hand-written XML) → management/setup → server/cmd.
