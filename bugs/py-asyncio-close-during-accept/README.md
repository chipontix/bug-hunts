# CPython `asyncio`: `Server.close()` while a connection is being accepted

| | |
|---|---|
| upstream issue | [python/cpython#109564](https://github.com/python/cpython/issues/109564) |
| upstream fix | [`ed5531c`](https://github.com/python/cpython/commit/ed5531cd7a9918a08b4a4df2200e733fa3625905) on the 3.14 branch ([PR #160879](https://github.com/python/cpython/pull/160879)), backport of [`5364bdc`](https://github.com/python/cpython/commit/5364bdce6b6f2b0e055057aef1002ef07b91a497) ([PR #160851](https://github.com/python/cpython/pull/160851)) |
| reproduced on | `python:3.14.10-slim` (pinned by digest), the newest 3.14 release; the fix is merged but not released yet |
| class | race between two event-loop steps (check-then-act across an `await` boundary) |
| license of the patch | PSF License 2.0 (CPython) |

## Symptom

A server that is closed while clients are connecting (restart loops, tests
that start and stop servers, graceful shutdown under load) reports
`Error on transport creation for incoming connection` with an
`AssertionError` to the loop's exception handler, leaves the accepted socket
open (`ResourceWarning: unclosed transport`), and later prints
`TypeError: 'NoneType' object is not iterable` from a transport's `__del__`.

```
AssertionError: accepted socket left open; loop errors: ['Error on transport creation for incoming connection: AssertionError()']
```

Full output: [`results/py-asyncio-close-during-accept/`](../../results/py-asyncio-close-during-accept/).

## Root cause

Accepting a connection takes two separate event-loop steps in
`selector_events.py`:

1. `_accept_connection` runs when the listening socket is readable. It calls
   `sock.accept()` and schedules a task, `_accept_connection2`.
2. Some iterations later that task calls `protocol_factory()` and builds the
   transport. The transport's constructor calls `server._attach(transport)`,
   which starts with `assert self._sockets is not None`.

`Server.close()` sets `_sockets = None` and stops listening, but it knows
nothing about connections already accepted in step 1 whose task has not run
yet. If `close()` lands between the two steps, the assertion fails inside the
transport constructor. `_accept_connection2` catches the exception and reports
it, but the half-built transport and its socket are never closed. When that
transport is garbage-collected, `__del__` calls `server._detach()`, which
calls `_wakeup()` a second time after `_waiters` was already set to `None`,
hence the `TypeError`.

It is a check-then-act race: the decision "this server is serving" was made
in step 1 and used in step 2, with an arbitrary number of other callbacks in
between.

## Fix

Re-check at the point of use. Right after `protocol_factory()` in
`_accept_connection2` (and in the equivalent proactor code for Windows):

```python
if server is not None and not server.is_serving():
    conn.close()
    return
```

The connection is dropped quietly, as it would have been had it arrived a
moment later. See [`fix.patch`](fix.patch).

## Regression test

[`test_close_during_accept.py`](test_close_during_accept.py). A race normally
needs luck or a loop of thousands of iterations; this one is forced: the
protocol factory itself calls `server.close()`, and the factory runs exactly
in the window between the two steps. The test then requires that the client
sees EOF, that `wait_closed()` returns, that no protocol was attached, and
that nothing was reported to the exception handler. The same trick is used by
the upstream test. Before the fix it fails every time; after, it passes.

## In one minute

asyncio accepts a socket in one callback and builds its transport in a later
one. `Server.close()` can run in between, and the second step assumed the
server was still open. The fix re-checks `is_serving()` where the decision
matters. The reproduction is deterministic because the protocol factory runs
inside the window, so it can close the server itself.
