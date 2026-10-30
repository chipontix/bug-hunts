"""Server.close() between accept() and transport creation (gh-109564).

Accepting a connection takes two event-loop steps: the listening socket's
reader callback calls accept(), then schedules a task that builds the
protocol and transport. If the server is closed in between, the transport
constructor calls Server._attach() on a server whose _sockets is already
None, and the AssertionError ends up in the loop's exception handler.

The race is made deterministic by closing the server from inside
protocol_factory, which runs in exactly that window.
"""
import asyncio
import unittest


class CloseDuringAccept(unittest.IsolatedAsyncioTestCase):
    async def test_close_between_accept_and_transport(self):
        loop = asyncio.get_running_loop()
        errors = []
        loop.set_exception_handler(lambda _loop, ctx: errors.append(ctx))
        made = []

        class Proto(asyncio.Protocol):
            def connection_made(self, transport):
                made.append(transport)

        def factory():
            server.close()  # the window: accepted, no transport yet
            return Proto()

        server = await loop.create_server(factory, "127.0.0.1", 0)
        host, port = server.sockets[0].getsockname()[:2]
        reader, writer = await asyncio.open_connection(host, port)
        try:
            async with asyncio.timeout(5):
                # The accepted connection must be dropped, not served...
                self.assertEqual(await reader.read(), b"")
                # ...and the closed server must finish closing.
                await server.wait_closed()
        except TimeoutError:
            self.fail(f"accepted socket left open; loop errors: {describe(errors)}")
        finally:
            writer.close()

        self.assertEqual(made, [], "protocol attached to a closed server")
        self.assertEqual(describe(errors), [], "errors reported to the loop")


def describe(errors):
    return [f"{c.get('message')}: {c.get('exception')!r}" for c in errors]


if __name__ == "__main__":
    unittest.main()
