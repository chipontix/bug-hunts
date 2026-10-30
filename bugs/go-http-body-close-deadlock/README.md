# Go `net/http`: concurrent `Body.Read` and `Body.Close` deadlock

| | |
|---|---|
| upstream issue | [golang/go#81404](https://github.com/golang/go/issues/81404), backport [golang/go#81411](https://github.com/golang/go/issues/81411) |
| upstream fix | [`aa6fc25`](https://github.com/golang/go/commit/aa6fc252ed3f092977a345d7db29547d7a553f13) on release-branch.go1.27 ([CL 830424](https://go-review.googlesource.com/c/go/+/830424)), cherry-pick of [`e51216d`](https://github.com/golang/go/commit/e51216de8e26247ee0f3d2cfa576233b0d29f542) |
| reproduced on | `golang:1.27.1-bookworm` (pinned by digest); first fixed release: go1.27.2 |
| class | deadlock: two completion callbacks, one handshake |
| license of the patch | BSD-3-Clause (Go) |

## Symptom

A goroutine is blocked in `resp.Body.Read`, another goroutine calls
`resp.Body.Close()` before EOF, and the server then finishes the body. On
1.27.1 `Close` returns but `Read` never does. This is a common shape: a
reader goroutine streaming a response and a supervisor closing the body on
cancel or shutdown.

```
    body_close_test.go:54: DEADLOCK: Body.Read did not return within 5s after the body ended
--- FAIL: TestConcurrentBodyReadAndEarlyClose (5.11s)
```

Full output: [`results/go-http-body-close-deadlock/`](../../results/go-http-body-close-deadlock/).

## Background: how the transport hands a connection back

For HTTP/1 each connection has a `readLoop` goroutine. After it delivers a
response it must not read the next response from the socket until the caller
is done with this body, so it waits on `waitForBodyRead`. The body is wrapped
in a `bodyEOFSignal` with two callbacks:

- `fn(err)`: called when `Read` returns a final error. It sends `isEOF` to
  `readLoop`, and on EOF waits on `eofc` until `readLoop` has decided what to
  do with the connection.
- `earlyCloseFn()`: called when `Close` happens before EOF. It sends `false`
  and also waits on `eofc`.

`readLoop` receives one value and sends on `eofc` once, then moves on to the
next request. If the connection dies instead, the deferred `close(eofc)`
releases everyone.

Go 1.27 added automatic draining: when the body is closed early and is small
(at most 256 KiB, given 50 ms), `readLoop` reads the rest itself so the
connection can go back to the pool instead of being closed.

## Root cause

With a `Read` in flight, both callbacks can fire for the same body:

1. `Close` runs `earlyCloseFn`: sends `false`, waits on `eofc`.
2. `readLoop` gets `false`, sends on `eofc` (`Close` returns), and starts
   draining the body.
3. The server sends the rest; the in-flight `Read` sees EOF and runs `fn`:
   sends `true` into the buffered channel, then waits on `eofc`.
4. The drain succeeded, so the connection is alive and goes back to the
   pool. `readLoop` loops to the next request and never sends on `eofc`
   again, and does not close it, because the connection is still alive.

The `Read` goroutine waits forever, holding the body's mutex. Before draining
existed, step 4 never happened: an early close always killed the connection,
and `close(eofc)` released the second waiter. The new feature turned a
harmless double notification into a deadlock.

## Fix

`bodyEOFSignal` now makes the two callbacks mutually exclusive: whichever runs
first clears both (`earlyCloseFn = nil; fn = nil`), so exactly one value is
sent and one `eofc` receive happens. The channel now carries the error instead
of a bool, so `readLoop` can tell "closed early" (`errClosedEarly`, drain and
maybe reuse) from "read failed" (don't reuse) from EOF. See
[`fix.patch`](fix.patch) (only `transport.go`; the upstream tests are left
out).

## Regression test

[`body_close_test.go`](body_close_test.go): an `httptest` server sends the
headers of a chunked response and holds the body. The client starts a reader
goroutine, waits 100 ms so it is blocked inside `Read`, calls `Close`, then
lets the server finish the body inside the 50 ms drain window. The test fails
if `Read` has not returned 5 s later, then checks that the drained connection
serves a second request.

The 100 ms sleep is the one non-deterministic part (upstream uses
`testing/synctest` with a fake network instead). How stable it is was
measured, not assumed: `make repeat BUG=go-http-body-close-deadlock N=20`
runs each mode 20 times; the counts are in
[`results/go-http-body-close-deadlock/repeat.txt`](../../results/go-http-body-close-deadlock/repeat.txt).

## In one minute

Two code paths, early `Close` and EOF from `Read`, each expected to be the
only one to report that a body was finished, and each waited for one
acknowledgement. A new feature, draining the body so the connection can be
reused, removed the side effect that used to wake the second waiter (closing
the connection). The fix makes the two reports mutually exclusive.
