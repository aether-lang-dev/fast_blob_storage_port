# fbs-core

**fbs-core** is a self-hosted, lightweight object storage ecosystem designed for single-node deployments like homelabs or small to medium projects. It provides a high-performance **AWS S3-compatible API**, acting as the core backend storage engine.

## Overview

The `fbs-core` backend handles all S3-compatible data operations, disk I/O, and exposes a Management API for external dashboards (such as a Web Dashboard or Terminal Dashboard). 

- **Language:** [Aether](https://github.com/aether-lang-org/aether) (compiles to C). Originally Go; see `BUILD-AETHER.md` for the port.
- **Storage Metadata:** SQLite (WAL mode) via `contrib.sqlite`
- **Object Storage:** Local File System (atomic write via `std.fs.write_atomic`)
- **HTTP:** `std.http` server; tests use the `std.spec` BDD framework (the stdlib
  absorption of the retired aeocha), plus `std.http.client.httptest` matchers
- **Build:** `./build.sh` (wraps `aeb cmd/.build.ae`), or `./bootstrap.sh` to
  install the toolchain first. Toolchain floors are pinned in `AETHER_PIN` /
  `AEB_PIN`.

## Features

### Core S3 API Capabilities
- **Object Operations:** `PUT`, `GET`, `DELETE`, `HEAD`
- **Bucket Operations:** `CREATE` (CreateBucket), `LIST` (ListObjectsV2)
- **Multipart Uploads:** `CreateMultipartUpload`, `UploadPart`, `CompleteMultipartUpload`

### Performance & Caching
- **Zero-Copy Transfers:** Utilizes `sendfile()` to stream objects from disk directly to the network.
- **In-Memory Caching:** Go Memory LRU Cache for hot SQLite metadata to prevent disk I/O bottlenecks.
- **SQLite Optimization:** Tuned with `synchronous=NORMAL` and `busy_timeout=5000` for high concurrency.

### Security & Data Integrity
- **Unified Authentication:** Protected S3 and Management API routes accept both AWS SigV4 and Bearer tokens. Authorization still depends on the stored user role.
- **First-Start Bootstrap:** On an empty database, create the initial admin once from localhost with `POST /api/setup/bootstrap`.
- **Path Sanitization:** Secure handling of object keys to prevent path traversal attacks.
- **Data Consistency:** Writes data to disk first (`.tmp/UUID` \u2192 rename), then inserts metadata into SQLite. Built-in startup reconciliation to purge orphaned data.
- **Upload Checksums:** Real-time validation of `Content-MD5` and `x-amz-checksum-*` headers on upload.
- **Signed Public Reads:** `/public/{bucket}/{key}` is reserved for signed read URLs, so `public` cannot be used as a bucket name.

## First Run

When the database has no users, call the loopback-only bootstrap endpoint from the server host:

```bash
curl -X POST http://127.0.0.1:9000/api/setup/bootstrap \
  -H 'Content-Type: application/json' \
  -d '{"display_name":"Admin User"}'
```

The response includes the initial admin Bearer token and SigV4 access key/secret once. Store them immediately; secrets are not returned by later management reads. `GET /api/setup/status` reports whether bootstrap is still required.

Management and S3 protected routes accept either `Authorization: Bearer ...` or AWS SigV4. SigV4 uses service scope `s3` and region `us-east-1`.

## Project Structure

- `cmd/`: Main application entry point (`main.ae`, `.build.ae`).
- `internal/`:
  - `auth/`: Authentication (AWS SigV4 & Bearer tokens) + token issuance.
  - `metadata/`: SQLite schema + repositories (buckets, objects, users, multipart, activity, management).
  - `s3/`: S3 API handlers, route wiring, XML, setup/management API, startup reconcile, `appstate.c`.
  - `s3compat/`, `responses/`, `publicread/`: region constant, JSON response helper, signed public-read URLs.
  - `storage/`: Disk storage engine (write/read/delete, path sanitizing, multipart).
- `lib/`: Reusable Aether libs — `crypto/` (`sigv4`, and `ctcompare` for
  constant-time signature compare). HMAC/MD5, URL-escaping, path cleaning and
  UUIDs all come from the stdlib now.
- `aethertests/`: `std.spec` test suites mirroring the source tree.
- `docs/`: Completed project documentation for architecture, configuration, APIs, storage, operations, and development.

## Documentation

The detailed project documentation lives in [`docs/README.md`](./docs/README.md). For Docker setup and first S3 operations, start with [`docs/quickstart.md`](./docs/quickstart.md).
