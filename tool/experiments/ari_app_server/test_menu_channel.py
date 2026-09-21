from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import tempfile
import time
import unittest
import subprocess
import sys
import json
from menu_channel import MenuChannel, call


class MenuChannelTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.channel = MenuChannel(Path(self.directory.name))
        self.channel.begin()

    def request(self):
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            request = self.channel.next()
            if request: return request
            time.sleep(.01)
        self.fail('No actual MCP request reached the app mailbox')

    def test_round_trip_returns_only_actual_app_result(self):
        with ThreadPoolExecutor() as pool:
            pending = pool.submit(call, self.channel.root, 'execute_menu_action',
                                  {'id': 'theme-dark', 'revision': 7}, 2)
            request = self.request()
            self.assertEqual(request['arguments']['id'], 'theme-dark')
            result = {'status': 'invoked', 'id': 'theme-dark'}
            self.channel.complete(request['requestId'], result)
            self.assertEqual(pending.result(), result)
            self.assertIsNone(self.channel.next(), 'must not deliver an action twice')
            self.channel.complete(request['requestId'], result)
            with self.assertRaises(ValueError):
                self.channel.complete(request['requestId'], {'status': 'failed'})

    def test_typed_fields_round_trip_and_reject_non_strings(self):
        args = {'id': 'word-fill', 'revision': 4, 'values': {'meaning': 'หนังสือ'}}
        with ThreadPoolExecutor() as pool:
            pending = pool.submit(call, self.channel.root, 'execute_menu_action', args, 2)
            request = self.request()
            self.assertEqual(request['arguments'], args)
            result = {'status': 'filled', 'id': 'word-fill'}
            self.channel.complete(request['requestId'], result)
            self.assertEqual(pending.result(), result)
        for values in [[], {'word': 42}, {'word': {'nested': 'x'}}, {'word': 'x' * 4001},
                       {str(i): 'x' for i in range(9)}]:
            with self.assertRaises(ValueError):
                call(self.channel.root, 'execute_menu_action', {**args, 'values': values}, .01)

    def test_cancel_and_late_result_cannot_cross_turn(self):
        with ThreadPoolExecutor() as pool:
            pending = pool.submit(call, self.channel.root, 'list_menu_actions', {}, 2)
            request = self.request()
            self.channel.end()
            self.assertIn(pending.result()['status'], {'cancelled', 'unavailable'})
            self.channel.begin()
            with self.assertRaises(ValueError):
                self.channel.complete(request['requestId'], {'status': 'invoked'})

    def test_no_app_response_is_timeout_not_success(self):
        self.assertEqual(call(self.channel.root, 'list_menu_actions', {}, .03),
                         {'status': 'timeout'})

    def test_paths_commands_unknown_tools_and_wrong_revision_types_rejected(self):
        for name, args in [('shell', {}), ('list_menu_actions', {'path': '../x'}),
                           ('execute_menu_action', {'id': 'x', 'revision': True})]:
            with self.assertRaises(ValueError): call(self.channel.root, name, args)

    def test_real_stdio_mcp_waits_for_application_receipt(self):
        context = self.channel.root / 'word.json'
        context.write_text('{}', encoding='utf-8')
        frames = [
            {'jsonrpc': '2.0', 'id': 1, 'method': 'initialize'},
            {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
            {'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'},
            {'jsonrpc': '2.0', 'id': 3, 'method': 'tools/call', 'params': {
                'name': 'execute_menu_action', 'arguments': {'id': 'theme-dark', 'revision': 4}}}]
        def run():
            return subprocess.run([sys.executable, str(Path(__file__).with_name('tutor_mcp.py')),
                '--context', str(context), '--menu', str(self.channel.root)],
                input='\n'.join(json.dumps(f) for f in frames)+'\n', text=True,
                encoding='utf-8', capture_output=True, timeout=5)
        with ThreadPoolExecutor() as pool:
            process = pool.submit(run)
            request = self.request()
            receipt = {'status': 'invoked', 'id': 'theme-dark'}
            self.channel.complete(request['requestId'], receipt)
            result = process.result()
        self.assertEqual(result.returncode, 0)
        responses = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual(len(responses[1]['result']['tools']), 4)
        self.assertEqual(responses[2]['result']['structuredContent'], receipt)
        self.assertFalse(responses[2]['result']['isError'])

    def test_real_stdio_mcp_preserves_verified_saved_status(self):
        context = self.channel.root / 'word.json'
        context.write_text('{}', encoding='utf-8')
        frames = [
            {'jsonrpc': '2.0', 'id': 1, 'method': 'initialize'},
            {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
            {'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'},
            {'jsonrpc': '2.0', 'id': 3, 'method': 'tools/call', 'params': {
                'name': 'execute_menu_action', 'arguments': {'id': 'word-save', 'revision': 4, 'values': {}} }}]
        def run():
            return subprocess.run([sys.executable, str(Path(__file__).with_name('tutor_mcp.py')),
                '--context', str(context), '--menu', str(self.channel.root)],
                input='\n'.join(json.dumps(f) for f in frames)+'\n', text=True,
                encoding='utf-8', capture_output=True, timeout=5)
        with ThreadPoolExecutor() as pool:
            process = pool.submit(run)
            request = self.request()
            receipt = {'status': 'saved', 'id': 'word-save'}
            self.channel.complete(request['requestId'], receipt)
            result = process.result()
        self.assertEqual(result.returncode, 0)
        responses = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual(len(responses[1]['result']['tools']), 4)
        self.assertEqual(responses[2]['result']['structuredContent'], receipt)
        self.assertFalse(responses[2]['result']['isError'])


if __name__ == '__main__': unittest.main()
