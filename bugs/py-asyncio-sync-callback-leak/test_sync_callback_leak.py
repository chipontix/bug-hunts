"""A plain-function client_connected_cb that raises (gh-155941).

asyncio.start_server() accepts a coroutine function or a plain function as
the per-connection callback. The coroutine branch reports an exception and
closes the transport; the plain-function branch let the exception escape
from StreamReaderProtocol.connection_made(), so nobody closed the transport:
the client hangs on an open connection and Server.wait_closed() never
returns.
"""
import asyncio
import unittest


class SyncCallbackRaises(unittest.IsolatedAsyncioTestCase):
    async def test_transport_closed_and_error_reported(self):
        loop = asyncio.get_running_loop()
        errors = []
        loop.set_exception_handler(lambda _loop, ctx: errors.append(ctx))

        def on_client(reader, writer):  # plain function, not async def
            raise RuntimeError("handler bug")

        server = await asyncio.start_server(on_client, "127.0.0.1", 0)
        host, port = server.sockets[0].getsockname()[:2]
        reader, writer = await asyncio.open_connection(host, port)
        try:
            try:
                async with asyncio.timeout(3):
                    data = await reader.read()
            except TimeoutError:
                self.fail("transport leaked: the server never closed the connection")
            self.assertEqual(data, b"")
        finally:
            writer.close()

        server.close()
        try:
            async with asyncio.timeout(3):
                await server.wait_closed()
        except TimeoutError:
            self.fail("transport leaked: Server.wait_closed() hangs")

        self.assertEqual(
            [c.get("message") for c in errors],
            ["Unhandled exception in client_connected_cb"],
        )
        self.assertIsInstance(errors[0]["exception"], RuntimeError)


if __name__ == "__main__":
    unittest.main()
