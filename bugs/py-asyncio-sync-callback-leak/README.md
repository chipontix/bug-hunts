# CPython `asyncio`: a raising plain-function `client_connected_cb` leaks the connection

| | |
|---|---|
| upstream issue | [python/cpython#155941](https://github.com/python/cpython/issues/155941) |
| upstream fix | [`fdc25ea`](https://github.com/python/cpython/commit/fdc25ea1b1f2f48135a6017927057e346b080c97) on the 3.14 branch ([PR #156273](https://github.com/python/cpython/pull/156273)), backport of [PR #155942](https://github.com/python/cpython/pull/155942) |
| reproduced on | `python:3.14.7-slim` (pinned by digest); first fixed release: 3.14.8 |
| class | resource leak on an error path |
| license of the patch | PSF License 2.0 (CPython) |

## Symptom

`asyncio.start_server(cb, ...)` accepts `cb` as either an `async def` or a
plain function. If a plain-function callback raises, the client stays
connected to a server that will never answer, and `server.wait_closed()`
hangs forever, which blocks graceful shutdown.

```
AssertionError: transport leaked: the server never closed the connection
ResourceWarning: unclosed transport <_SelectorSocketTransport fd=8>
```

Full output: [`results/py-asyncio-sync-callback-leak/`](../../results/py-asyncio-sync-callback-leak/).

## Root cause

`StreamReaderProtocol.connection_made()` (`Lib/asyncio/streams.py`) calls the
user callback and then branches on its result:

- If the result is a coroutine, it wraps it in a task with a done-callback
  that reports an exception as `Unhandled exception in client_connected_cb`
  and closes the transport.
- If the callback was a plain function, it has already run, and an exception
  propagates out of `connection_made()`.

`connection_made()` itself runs as a `call_soon` callback scheduled by the
transport. The event loop catches the exception, logs a generic
`Exception in callback ...`, and moves on. No code on that path owns the
transport any more, so it is never closed: the socket stays open, the server
keeps counting the client as active, and `wait_closed()` waits for a client
that will never go away.

The cleanup existed, but only on one of the two branches.

## Fix

Wrap the call in `try/except Exception`: report the error with the same
message as the coroutine branch, close the transport, and return. See
[`fix.patch`](fix.patch).

## Regression test

[`test_sync_callback_leak.py`](test_sync_callback_leak.py): a server with a
plain callback that raises; the client must see EOF within 3 s,
`wait_closed()` must return within 3 s, and exactly one
`Unhandled exception in client_connected_cb` must reach the loop's exception
handler. Before the fix the first timeout fires; after, the test passes.

## In one minute

The library supports two kinds of callback and had error handling for only
one. A synchronous exception escaped into the event loop, which logs and
continues, so the connection had no owner and was never closed. That one
leaked socket also made server shutdown hang. The fix gives the synchronous
branch the same cleanup as the async one.
