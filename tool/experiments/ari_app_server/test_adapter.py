import asyncio
import json
import os
from pathlib import Path
import sys
import unittest

try:
    from adapter import Client, RpcError, ProtocolError, IsolatedHome
except ImportError:
    Client = None


class AdapterTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.assertIsNotNone(Client, 'stdio adapter must exist')
        self.home = IsolatedHome(dict(os.environ, OPENAI_API_KEY='sentinel',
                                      CODEX_AUTH_JSON='sentinel', HTTP_PROXY='sentinel'))
        self.addCleanup(self.home.close)
        self.client = await Client.start(
            [sys.executable, '-I', str(Path(__file__).with_name('fake_server.py'))],
            self.home.cwd, self.home.env)
        self.addAsyncCleanup(self.client.close)

    async def test_out_of_order_and_notifications(self):
        a = asyncio.create_task(self.client.request('hold', {'value': 'first'}))
        await self.client.next_event(2)  # deterministic acknowledgement of hold
        b = await self.client.request('release', {})
        self.assertEqual(b, 'second')
        self.assertEqual(await a, 'first')
        self.assertEqual((await self.client.next_event(2))['method'], 'released')

    async def test_error_does_not_expose_payload(self):
        with self.assertRaises(RpcError) as caught:
            await self.client.request('error', {})
        self.assertEqual(caught.exception.code, -32000)
        self.assertNotIn('secret', str(caught.exception))
        self.assertEqual(await self.client.request('ping', {}), 'pong')

    async def test_timeout_late_reply_cannot_complete_next_request(self):
        with self.assertRaises(TimeoutError):
            await self.client.request('hold', {'value': 'late'}, timeout=.05)
        await self.client.next_event(2)
        self.assertEqual(await self.client.request('release', {}), 'second')
        self.assertEqual(await self.client.request('ping', {}), 'pong')

    async def test_task_cancel_discards_late_reply(self):
        task = asyncio.create_task(self.client.request('hold', {'value': 'late'}))
        await self.client.next_event(2)
        task.cancel()
        with self.assertRaises(asyncio.CancelledError):
            await task
        await self.client.request('release', {})
        self.assertEqual(await self.client.request('ping', {}), 'pong')

    async def test_login_cancel_drops_queued_and_late_completion(self):
        await self.client.request('queue-login-event', {})
        self.assertEqual(await self.client.cancel_login('fake-login'), {'status': 'canceled'})
        self.assertEqual((await self.client.next_event(2))['method'], 'after-cancel')
        with self.assertRaises(TimeoutError):
            await self.client.next_event(.05)

    async def test_eof_fails_pending(self):
        with self.assertRaises(EOFError):
            await self.client.request('die', {}, timeout=2)

    async def test_invalid_json_fails_pending(self):
        with self.assertRaises(ProtocolError):
            await self.client.request('malformed', {}, timeout=2)

    async def test_malformed_response_envelope_fails_pending(self):
        with self.assertRaises(ProtocolError):
            await self.client.request('invalid-envelope', {}, timeout=2)

    async def test_close_terminates_owned_child_ignoring_eof(self):
        await self.client.request('ignore-eof', {})
        await asyncio.wait_for(self.client.close(), 6)
        self.assertIsNotNone(self.client.process.returncode)

    async def test_closing_session_does_not_deliver_exit_notifications(self):
        await self.client.request('late-on-exit', {})
        await self.client.close()
        with self.assertRaises(EOFError):
            await self.client.next_event(.1)

    async def test_close_fails_pending_and_discards_session_events(self):
        task = asyncio.create_task(self.client.request('hold', {'value': 'late'}))
        await self.client.next_event(2)
        await self.client.request('queue-login-event', {})
        await self.client.close()
        with self.assertRaises(EOFError):
            await task
        with self.assertRaises(EOFError):
            await self.client.next_event(.1)
        with self.assertRaises(EOFError):
            await self.client.request('ping', {})
        self.assertIsNotNone(self.client.process.returncode)
        await self.client.close()

    async def test_server_requests_are_rejected_without_credentials(self):
        self.assertEqual(await self.client.request('server-request', {}), -32601)

    async def test_child_environment_and_cwd_are_isolated(self):
        result = await self.client.request('environment', {})
        self.assertEqual(Path(result['cwd']), self.home.cwd)
        self.assertEqual(result['files'], [])
        self.assertEqual(result['env']['CODEX_HOME'], str(self.home.root / 'home'))
        self.assertNotIn('OPENAI_API_KEY', result['env'])
        self.assertNotIn('CODEX_AUTH_JSON', result['env'])
        self.assertNotIn('HTTP_PROXY', result['env'])


class IsolationTests(unittest.TestCase):
    def test_cleanup_rejects_redirected_root(self):
        home = IsolatedHome()
        original = home.root
        try:
            home.root = original.parent
            with self.assertRaises(ValueError):
                home.close()
            self.assertTrue(original.exists())
        finally:
            home.root = original
            home.close()

    def test_allowlist_and_cleanup(self):
        self.assertIsNotNone(Client, 'isolation implementation must exist')
        parent = dict(os.environ)
        contaminated = dict(parent, OPENAI_API_KEY='sentinel', CODEX_AUTH_JSON='sentinel',
                            ANTHROPIC_API_KEY='sentinel', AWS_ACCESS_KEY_ID='sentinel',
                            CUSTOM_TOKEN='sentinel', HTTP_PROXY='sentinel',
                            CODEX_HOME='forbidden', PATH='forbidden')
        home = IsolatedHome(contaminated)
        root = home.root
        try:
            self.assertFalse(any(v in ('sentinel', 'forbidden') for v in home.env.values()))
            self.assertIn('cli_auth_credentials_store = "file"',
                          (root / 'home' / 'config.toml').read_text())
            self.assertFalse((root / 'home' / 'auth.json').exists())
            self.assertEqual(dict(os.environ), parent)
        finally:
            home.close()
        self.assertFalse(root.exists())
        home.close()


if __name__ == '__main__':
    unittest.main()
