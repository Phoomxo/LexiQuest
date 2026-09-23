import asyncio
import json
from pathlib import Path
import tempfile
import unittest
try:
    from chat_bridge import ChatSession, ChatBridge
except ModuleNotFoundError:
    ChatSession = ChatBridge = None
from login_bridge import BridgeError

BINDING = {'ownerId': 'owner-a', 'accountId': 'local-a', 'generation': 1}
WORD = {'id': 'bottle-id', 'spelling': 'bottle', 'meaning': 'ขวด', 'partOfSpeech': 'noun', 'revision': 1}


class FakeClient:
    def __init__(self, path):
        self.context_path = path
        self.calls = []
        self.events = asyncio.Queue()
        self.authenticated = True
        self.hang = False
    async def request(self, method, params=None, timeout=5):
        self.calls.append((method, params))
        if method == 'account/read':
            return {'account': {'type': 'chatgpt'} if self.authenticated else None}
        if method == 'thread/start': return {'thread': {'id': 'thread-one'}}
        if method == 'turn/start':
            if not self.hang:
                for item in [
                    {'type': 'mcpToolCall', 'id': 'tool-one', 'server': 'lexiquest',
                     'tool': 'read_selected_word', 'status': 'completed',
                     'result': {'structuredContent': WORD, 'content': []}},
                    {'type': 'agentMessage', 'id': 'reply-one', 'phase': 'final_answer', 'text': 'bottle หมายถึงขวด'}]:
                    self.events.put_nowait({'method': 'item/completed', 'params': {
                        'threadId': 'thread-one', 'turnId': 'turn-one', 'item': item}})
                self.events.put_nowait({'method': 'turn/completed', 'params': {
                    'threadId': 'thread-one', 'turn': {'id': 'turn-one', 'status': 'completed'}}})
            return {'turn': {'id': 'turn-one'}}
        return {}
    async def next_event(self, timeout=5):
        return await asyncio.wait_for(self.events.get(), timeout)
    async def cancel_login(self, _): pass
    async def close(self): pass


class ChatBridgeTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.assertIsNotNone(ChatSession, 'Live chat session implementation is missing')
        self.directory = tempfile.TemporaryDirectory(prefix='ari-chat-test-')
        self.addCleanup(self.directory.cleanup)
        self.client = FakeClient(Path(self.directory.name) / 'selected.json')
        async def start(): return self.client, lambda: None
        self.session = ChatSession(start)
        self.session.client = self.client
        self.bridge = ChatBridge(self.session, 'x'*43)
        self.addAsyncCleanup(self.session.close)

    async def test_reply_uses_real_turn_protocol_and_reports_tool_receipt(self):
        await self.session.connect(BINDING, WORD)
        reply = await self.session.reply(BINDING, 'อธิบายคำนี้', 'request-1')
        self.assertEqual(reply['text'], 'bottle หมายถึงขวด')
        self.assertEqual(reply['tools'][0]['data'], WORD)
        self.assertEqual(json.loads(self.client.context_path.read_text(encoding='utf-8')), WORD)
        self.assertEqual(self.client.calls[1][1]['sandbox'], 'read-only')

    async def test_reconnect_after_owned_home_cleanup_uses_new_menu_channel(self):
        await self.session.connect(BINDING, WORD)
        old_menu = self.session.menu
        old_menu.begin()
        self.session.cleanup = self.directory.cleanup
        await self.session.close()
        self.assertFalse(old_menu.root.exists())
        fresh = tempfile.TemporaryDirectory(prefix='ari-chat-reconnect-')
        self.addCleanup(fresh.cleanup)
        self.session.client = FakeClient(Path(fresh.name) / 'selected.json')
        connected = await self.session.connect({**BINDING, 'generation': 2}, None)
        self.assertEqual(connected, {'ready': True})
        self.assertIsNot(self.session.menu, old_menu)
        self.assertEqual(self.session.menu.root.parent, Path(fresh.name))
        self.assertIsNone(self.session.menu.next())
        reply = await self.session.reply(
            {**BINDING, 'generation': 2}, 'current screen', 'new-request')
        self.assertEqual(reply['text'], 'bottle หมายถึงขวด')
        await self.session.close()
        await self.session.close()

    async def test_followup_keeps_thread_and_duplicate_request_does_not_start_turn(self):
        await self.session.connect(BINDING, WORD)
        first = await self.session.reply(BINDING, 'อธิบาย', 'request-1')
        self.assertEqual(first, await self.session.reply(BINDING, 'อธิบาย', 'request-1'))
        await self.session.reply(BINDING, 'ยกตัวอย่างเพิ่ม', 'request-2')
        self.assertEqual(sum(m == 'thread/start' for m, _ in self.client.calls), 1)
        self.assertEqual(sum(m == 'turn/start' for m, _ in self.client.calls), 2)

    async def test_completed_tool_with_error_result_is_not_success(self):
        await self.session.connect(BINDING, WORD)
        self.client.hang = True
        self.client.events.put_nowait({'method': 'item/completed', 'params': {
            'threadId': 'thread-one', 'turnId': 'turn-one', 'item': {
                'type': 'mcpToolCall', 'id': 't', 'server': 'lexiquest',
                'tool': 'read_selected_word', 'status': 'completed',
                'result': {'isError': True, 'content': []}}}})
        self.client.events.put_nowait({'method': 'item/completed', 'params': {
            'threadId': 'thread-one', 'turnId': 'turn-one', 'item': {
                'type': 'agentMessage', 'id': 'r', 'text': 'Cannot read word'}}})
        self.client.events.put_nowait({'method': 'turn/completed', 'params': {
            'threadId': 'thread-one', 'turn': {'id': 'turn-one', 'status': 'completed'}}})
        result = await self.session.reply(BINDING, 'explain', 'error-test')
        self.assertEqual(result['tools'][0]['status'], 'failed')

    async def test_http_transport_preserves_thai_and_rejects_origin(self):
        await self.session.connect(BINDING, WORD)
        server = await asyncio.start_server(self.bridge.handle, '127.0.0.1', 0, limit=4096)
        self.addAsyncCleanup(server.wait_closed)
        self.addCleanup(server.close)
        port = server.sockets[0].getsockname()[1]
        async def post(origin=False):
            reader, writer = await asyncio.open_connection('127.0.0.1', port)
            payload = json.dumps({'binding': BINDING, 'message': 'explain', 'requestId':'wire-1'}).encode()
            headers = ('POST /reply HTTP/1.1\r\nHost: 127.0.0.1:8765\r\n'
                       'Content-Type: application/json\r\nAuthorization: Bearer ' + 'x'*43 + '\r\n'
                       + ('Origin: https://example.test\r\n' if origin else '')
                       + f'Content-Length: {len(payload)}\r\n\r\n')
            writer.write(headers.encode()+payload); await writer.drain()
            raw = await asyncio.wait_for(reader.read(), 3)
            writer.close(); await writer.wait_closed()
            return raw
        raw = await post()
        self.assertTrue(raw.startswith(b'HTTP/1.1 200'))
        self.assertEqual(json.loads(raw.split(b'\r\n\r\n')[1])['tools'][0]['data'], WORD)
        self.assertTrue((await post(True)).startswith(b'HTTP/1.1 403'))
        self.assertEqual(sum(m == 'turn/start' for m,_ in self.client.calls), 1)

    async def test_wrong_owner_is_rejected_before_turn(self):
        await self.session.connect(BINDING, WORD)
        with self.assertRaises(BridgeError):
            await self.session.reply({**BINDING, 'ownerId': 'other'}, 'hello', 'request-1')
        self.assertFalse(any(m == 'turn/start' for m, _ in self.client.calls))

    async def test_cancel_interrupts_provider_and_discards_late_reply(self):
        await self.session.connect(BINDING, WORD)
        self.client.hang = True
        task = asyncio.create_task(self.session.reply(BINDING, 'hello', 'request-1'))
        for _ in range(50):
            if any(m == 'turn/start' for m, _ in self.client.calls): break
            await asyncio.sleep(.01)
        await self.session.cancel()
        with self.assertRaises(BridgeError): await asyncio.wait_for(task, 2)
        self.assertTrue(any(m == 'turn/interrupt' for m, _ in self.client.calls))

    async def test_unauthenticated_chat_and_arbitrary_rpc_are_unavailable(self):
        self.client.authenticated = False
        with self.assertRaises(BridgeError): await self.session.connect(BINDING, WORD)
        with self.assertRaises(BridgeError):
            await self.bridge.dispatch('/rpc', {'method': 'command/exec'}, 'x'*43)
        self.assertFalse(any(m == 'thread/start' for m, _ in self.client.calls))


if __name__ == '__main__': unittest.main()
