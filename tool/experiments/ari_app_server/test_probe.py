import unittest

try:
    from probe import probe_session, ProbeFailure
except ImportError:
    probe_session = None


class ScriptedClient:
    def __init__(self, account=None):
        self.account = account
        self.calls = []

    async def request(self, method, params=None, timeout=5):
        self.calls.append((method, params))
        if method == 'initialize':
            return {'userAgent': 'synthetic', 'platformFamily': 'windows',
                    'platformOs': 'windows', 'codexHome': 'private-path'}
        if method == 'account/read':
            return {'account': self.account, 'requiresOpenaiAuth': True}
        if method == 'account/logout':
            return {}
        raise AssertionError('Forbidden request')

    async def notify(self, method, params=None):
        self.calls.append((method, params))

    async def next_event(self, timeout=5):
        return {'method': 'account/updated', 'params': {'authMode': None, 'planType': None}}


class ProbeTests(unittest.IsolatedAsyncioTestCase):
    async def test_only_safe_wire_operations_and_sanitized_evidence(self):
        self.assertIsNotNone(probe_session, 'real-binary smoke driver must exist')
        client = ScriptedClient()
        result = await probe_session(client)
        self.assertEqual([m for m, p in client.calls],
                         ['initialize', 'initialized', 'account/read', 'account/logout', 'account/read'])
        self.assertEqual(client.calls[2][1], {'refreshToken': False})
        self.assertIsNone(client.calls[3][1])
        self.assertEqual(result['beforeLogout']['account'], None)
        self.assertEqual(result['afterLogout']['account'], None)
        self.assertNotIn('private-path', str(result))

    async def test_unexpected_account_aborts_before_logout(self):
        self.assertIsNotNone(probe_session, 'real-binary smoke driver must exist')
        client = ScriptedClient({'type': 'chatgpt', 'email': 'private@example.test'})
        with self.assertRaises(ProbeFailure) as caught:
            await probe_session(client)
        self.assertNotIn('private', str(caught.exception))
        self.assertEqual([m for m, p in client.calls], ['initialize', 'initialized', 'account/read'])


if __name__ == '__main__':
    unittest.main()
