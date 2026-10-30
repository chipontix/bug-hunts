# bug-hunts

Six real, already fixed bugs from Go, CPython, {fmt} and nlohmann/json,
each reproduced in Docker on the exact upstream version that still has it,
explained, and pinned down with a regression test that fails before the
upstream fix and passes after it. One command runs all of them both ways.

These are reproductions and write-ups of other people's fixes. The fixes were
written by the upstream authors credited in each `fix.patch`; nothing here was
contributed upstream.

| bug | language | class | upstream | reproduced on |
|---|---|---|---|---|
| [`go-flate-preset-dict`](bugs/go-flate-preset-dict/) | Go | wrong buffer boundary, silent data corruption | [golang/go#80538](https://github.com/golang/go/issues/80538) | go1.27.1 |
| [`go-http-body-close-deadlock`](bugs/go-http-body-close-deadlock/) | Go | deadlock between `Body.Read` and `Body.Close` | [golang/go#81404](https://github.com/golang/go/issues/81404) | go1.27.1 |
| [`py-asyncio-close-during-accept`](bugs/py-asyncio-close-during-accept/) | Python | race across two event-loop steps | [python/cpython#109564](https://github.com/python/cpython/issues/109564) | CPython 3.14.10 |
| [`py-asyncio-sync-callback-leak`](bugs/py-asyncio-sync-callback-leak/) | Python | socket leak on an error path, shutdown hangs | [python/cpython#155941](https://github.com/python/cpython/issues/155941) | CPython 3.14.7 |
| [`cpp-fmt-error-code-oob`](bugs/cpp-fmt-error-code-oob/) | C++ | bounds check after the dereference (read at `end`) | [fmtlib/fmt#4934](https://github.com/fmtlib/fmt/pull/4934) | fmt `7071103` |
| [`cpp-json-update-self-alias`](bugs/cpp-json-update-self-alias/) | C++ | aliasing: iterator invalidation, use after free | [nlohmann/json#5641](https://github.com/nlohmann/json/issues/5641) | json `1d675cd` |

Each bug's README has the symptom, the root cause, the upstream fix, how the
test works, and a one-minute summary.

## Result

From `make verify` on the machine below; raw output of every run is in
[`results/`](results/) (`<bug>/before.log`, `<bug>/after.log`,
[`summary.md`](results/summary.md), [`environment.txt`](results/environment.txt)).

| bug | before fix | after fix | run time, s (before / after) | marker in failing output |
|---|---|---|---|---|
| cpp-fmt-error-code-oob | FAIL | PASS | 8.0 / 5.9 | `heap-buffer-overflow` |
| cpp-json-update-self-alias | FAIL | PASS | 16.7 / 16.3 | `heap-use-after-free` |
| go-flate-preset-dict | FAIL | PASS | 7.1 / 7.5 | `dictionary leaked into output` |
| go-http-body-close-deadlock | FAIL | PASS | 17.7 / 13.1 | `DEADLOCK` |
| py-asyncio-close-during-accept | FAIL | PASS | 6.4 / 1.4 | `Error on transport creation for incoming connection: AssertionError` |
| py-asyncio-sync-callback-leak | FAIL | PASS | 4.3 / 0.9 | `transport leaked` |

Whole run (`make verify`, image layers already cached by an earlier run): **127.6 s** wall time
([`results/environment.txt`](results/environment.txt)). The shared VM was busy with other
projects' containers, so treat the times as rough.

"FAIL" means the test exited 1 and its output contains the bug's marker
(right column), so a broken build or an unrelated failure cannot pass as a
reproduction. Run times are one `docker run` each, image already built: they
include container start, applying the patch (after), compiling (C++, and Go's
rebuild of the patched package) and the test. The timeouts in the
deadlock and leak tests (3–5 s) dominate their "before" times.

Stability of the one timing-dependent reproduction, `go-http-body-close-deadlock`:
**20/20** runs failed before the fix and **20/20** passed after it ([`results/go-http-body-close-deadlock/repeat.txt`](results/go-http-body-close-deadlock/repeat.txt),
`make repeat BUG=go-http-body-close-deadlock N=20`).

**Hardware** (from [`results/environment.txt`](results/environment.txt), written by
`scripts/environment.sh`). Apple M4 Max (16 cores, 48 GiB), macOS 26.6.2; Docker 29.5.2 in
a colima 0.10.3 VM with 4 vCPU and 6 GiB (5.8 GiB visible to Docker; aarch64, kernel 6.8.0), shared with
other workloads. CI runs the same `make verify` on GitHub's `ubuntu-latest`
(x86_64); every base image is multi-arch and pinned by digest.

## Run

Needs Docker, bash and python3 (the harness uses it for timing).

```bash
make verify                        # all bugs, before and after, prints the table
make go-flate-preset-dict          # one bug
make repeat BUG=go-http-body-close-deadlock N=20
make clean                         # removes the bughunts-* images only
```

Or by hand, for one bug:

```bash
docker build -t bughunts-go-flate-preset-dict -f bugs/go-flate-preset-dict/Dockerfile .
docker run --rm bughunts-go-flate-preset-dict before   # exits 1
docker run --rm bughunts-go-flate-preset-dict after    # exits 0
```

**`error getting credentials ... docker-credential-desktop: executable file not found`.**
This happens when `~/.docker/config.json` has `"credsStore": "desktop"` (left by
Docker Desktop) but the helper is not installed, e.g. with colima. Without
editing the global config, point Docker at a separate config directory for
this repo:

```bash
mkdir -p ~/.config/bughunts-docker
echo '{"auths":{}}' > ~/.config/bughunts-docker/config.json
ln -s ~/.docker/cli-plugins ~/.config/bughunts-docker/cli-plugins   # keep buildx
export DOCKER_CONFIG=~/.config/bughunts-docker
export DOCKER_HOST=unix://$HOME/.colima/default/docker.sock         # colima's socket
make verify
```

## Layout

```
bugs/<bug>/Dockerfile   pinned upstream version (image digest or source commit)
bugs/<bug>/fix.patch    the upstream fix, source hunks only, with origin and license
bugs/<bug>/*_test.*     regression test (own code)
bugs/<bug>/README.md    write-up
scripts/entry.sh        container entrypoint: `before` runs the test, `after` applies fix.patch first
scripts/verify.sh       builds, runs both modes, checks exit codes and markers, writes results/
scripts/repeat.sh       N runs per mode, for timing-dependent reproductions
results/                raw output of the last local run
```

## How a reproduction works

Each image contains the vulnerable upstream code at a fixed version and the
upstream fix as a patch file. `entry.sh before` builds (where needed) and runs
the test as is; `entry.sh after` applies `fix.patch` with `patch --forward`
and runs the same test. Patching inside the container on every run proves
that the patch applies to that exact version, and keeps "before" and "after"
identical except for the fix. Exit codes: 0 pass, 1 test failed (assertion,
sanitizer report, timeout), 2 patch did not apply, 3 build failed.

How the upstream code gets into the image depends on the project:

- **Go standard library**: the official `golang:1.27.1` image. The toolchain
  compiles the standard library from `$GOROOT/src` on demand, so patching
  `/usr/local/go/src/...` is enough for `go test` to pick up the fix.
- **CPython `asyncio`**: pure Python, so the official `python:3.14.x-slim`
  image is patched in `/usr/local/lib/python3.14/`.
- **{fmt}, nlohmann/json**: header-only; the image downloads the source
  tarball of the parent of the fix commit from GitHub at build time and the
  test compiles against it with GCC 15.3.0 and ASan/UBSan.

No upstream source is stored in this repository other than the hunks in the
`fix.patch` files.

## Design decisions

**Why these bugs.** Each one has a cause that fits in a paragraph and a class
that comes up in real backend work: a buffer boundary, a deadlock between
two goroutines, a race across event-loop steps, a resource leak on an error
path, a bounds check in the wrong order, aliasing between an argument and
`*this`. All six are recent (fixed between August and October 2026), so the
vulnerable versions are still the ones people run, and three of the fixes are
not in a release yet. Security issues were left out on purpose: the point is
the debugging, not an exploit.

**Why the standard library and header-only libraries.** Go's toolchain
rebuilds the standard library from source and asyncio is plain Python, so the
official images can be patched in place instead of building a toolchain or
an interpreter from source. That keeps image builds short and makes the "after" run differ from "before" by the
upstream patch and nothing else.

**Why pin the parent commit for the C++ libraries.** The fixes are on the
development branch after the last release. Pinning the fix commit's parent
means the upstream patch applies without edits, which is a stronger claim
than "a similar fix applied to an older release".

**Why own tests instead of the upstream ones.** The upstream tests live in
test suites that need the whole project's test harness (`test.support`,
Go's internal fake-network helpers, googletest, doctest). The tests here use only public
APIs, run against the installed library, and each failure message names the
bug. Expected values match the upstream tests where those exist.

**Why a marker check.** A test that fails for a different reason (a typo, a
missing tool in the image) would otherwise count as "reproduced". Each image
declares the string its failure must contain (`LABEL bughunts.expect`), and
`verify.sh` checks it.

**Making races deterministic.** The asyncio race closes the server from
inside the protocol factory, which runs exactly in the window between accept
and transport creation, so it fails on every run. The net/http deadlock
needs a reader blocked in `Read` before `Close`; a 100 ms sleep does that,
and `make repeat` measures how stable it is instead of assuming it.

## Limitations

- `go-http-body-close-deadlock` relies on a sleep and on the transport's
  50 ms drain window. A very slow or overloaded machine could make it pass
  before the fix; `make repeat` is there to check.
- `cpp-fmt-error-code-oob` is compiled at `-O0`: at `-O1` the same test ran
  clean under ASan in our runs, because the compiler may drop the stray load.
- `cpp-json-update-self-alias`: ASan stops at the first error, so in the
  "before" run only the first two of four cases are reached.
- `py-asyncio-close-during-accept` is reproduced on the selector event loop
  (Linux). The fix also patches the Windows proactor loop, which is not
  exercised here.
- The fix patches carry only the source hunks. Upstream's own tests, docs
  and the amalgamated `single_include/` copy of nlohmann/json are left out.

## Third-party code

| what | where it is used | license |
|---|---|---|
| Go 1.27.1 (`golang` image) and the patch hunks in `bugs/go-*/fix.patch` | Go reproductions | BSD-3-Clause |
| CPython 3.14.7 / 3.14.10 (`python` image) and `bugs/py-*/fix.patch` | Python reproductions | PSF License 2.0 |
| {fmt} at `7071103` (downloaded at build) and `bugs/cpp-fmt-*/fix.patch` | C++ reproduction | MIT |
| nlohmann/json at `1d675cd` (downloaded at build) and `bugs/cpp-json-*/fix.patch` | C++ reproduction | MIT |
| GCC 15.3.0 (`gcc` image) | C++ build | GPL-3.0 with runtime library exception |
| Debian packages `patch` | applying fixes | GPL-3.0 |

Everything else is MIT, see [LICENSE](LICENSE).
