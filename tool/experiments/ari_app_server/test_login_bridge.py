import asyncio
import unittest
from login_bridge import LoginSession, Bridge, BridgeError


class FakeClient:
    def __init__(self):
        self.calls = []
        self.closed = False
        self.logged_in = False
    async def request(self, method, params=None, timeout=5):
        self.calls.append((method, params))
        if method == 'account/login/start':
            return {'type': 'chatgptDeviceCode', 'loginId': 'local-login',
                    'verificationUrl': 'https://auth.openai.com/codex/device',
                    'userCode': 'TEST-CODE'}
        if method == 'account/read':
            return {'account': {'type': 'chatgpt', 'email': 'never-forward',
                                'planType': 'pro'} if self.logged_in else None}
        return {}
    async def cancel_login(self, login_id):
        self.calls.append(('account/login/cancel', {'loginId': login_id}))
    async def close(self): self.closed = True


class LoginBridgeTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.client = FakeClient()
        async def start(): return self.client, lambda: None
        self.session = LoginSession(start)
        self.bridge = Bridge(self.session, 'x' * 43)
    async def asyncTearDown(self): await self.session.close()
    async def test_reject_unauthenticated_before_provider_call(self):
        with self.assertRaises(BridgeError):
            await self.bridge.dispatch('/login', {}, 'wrong')
        self.assertEqual(self.client.calls, [])
    async def test_only_device_flow_and_minimal_status(self):
        result = await self.bridge.dispatch('/login', {}, 'x' * 43)
        self.assertEqual(set(result), {'verificationUrl', 'userCode'})
        self.assertEqual(self.client.calls[0],
                         ('account/login/start', {'type': 'chatgptDeviceCode'}))
        self.client.logged_in = True
        self.assertEqual(await self.bridge.dispatch('/status', {}, 'x' * 43),
                         {'authenticated': True, 'inferenceEnabled': False})
    async def test_logout_destroys_private_child(self):
        await self.session.login()
        await self.session.close()
        self.assertTrue(self.client.closed)
        self.assertIn(('account/logout', None), self.client.calls)
    async def test_no_inference_or_arbitrary_rpc_proxy(self):
        for path in ['/reply', '/thread/start', '/account/read', '/rpc']:
            with self.assertRaises(BridgeError):
                await self.bridge.dispatch(path, {}, 'x' * 43)
        self.assertEqual(self.client.calls, [])
    async def test_reject_payloads_and_browser_origins(self):
        with self.assertRaises(BridgeError):
            await self.bridge.dispatch('/login', {'apiKey': 'never'}, 'x' * 43)
        self.assertEqual(self.client.calls, [])
    async def test_untrusted_verification_url_never_returned(self):
        original = self.client.request
        async def malicious(method, params=None, timeout=5):
            result = await original(method, params, timeout)
            if method == 'account/login/start':
                result['verificationUrl'] = 'https://example.com/collect'
            return result
        self.client.request = malicious
        with self.assertRaises(BridgeError): await self.session.login()
        self.assertTrue(self.client.closed)
    async def test_status_does_not_start_child_or_read_existing_account(self):
        self.assertEqual(await self.session.status(),
                         {'authenticated': False, 'inferenceEnabled': False})
        self.assertEqual(self.client.calls, [])

    async def test_cancelled_login_reaps_child(self):
        pending = asyncio.Event()
        original = self.client.request
        async def blocked(method, params=None, timeout=5):
            if method == 'account/login/start':
                pending.set()
                await asyncio.Event().wait()
            return await original(method, params, timeout)
        self.client.request = blocked
        work = asyncio.create_task(self.session.login())
        await pending.wait()
        work.cancel()
        with self.assertRaises(asyncio.CancelledError): await work
        self.assertTrue(self.client.closed)

    async def test_http_loopback_accepts_native_json_charset_and_rejects_origin(self):
        server = await asyncio.start_server(self.bridge.handle, '127.0.0.1', 0)
        async with server:
            port = server.sockets[0].getsockname()[1]
            async def send(origin=''):
                reader, writer = await asyncio.open_connection('127.0.0.1', port)
                writer.write(('POST /status HTTP/1.1\r\nHost: 127.0.0.1:8765\r\n'
                    'Content-Type: application/json; charset=utf-8\r\nContent-Length: 2\r\n'
                    'Authorization: Bearer ' + 'x'*43 + '\r\n' + origin + '\r\n{}').encode())
                await writer.drain()
                result = await reader.read()
                writer.close(); await writer.wait_closed()
                return result
            self.assertIn(b'200 Response', await send())
            self.assertIn(b'403 Response', await send('Origin: https://evil.test\r\n'))

if __name__ == '__main__': unittest.main()
