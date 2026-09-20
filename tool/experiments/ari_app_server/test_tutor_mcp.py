import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class TutorMcpTests(unittest.TestCase):
    def exchange(self, calls, word=None):
        with tempfile.TemporaryDirectory(prefix='ari-mcp-test-') as directory:
            context = Path(directory) / 'selected.json'
            context.write_text(json.dumps(word or {
                'id': 'word-bottle', 'spelling': 'bottle', 'meaning': 'ขวด',
                'partOfSpeech': 'noun', 'revision': 3}), encoding='utf-8')
            frames = [
                {'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {
                    'protocolVersion': '2025-06-18', 'capabilities': {},
                    'clientInfo': {'name': 'test', 'version': '1'}}},
                {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
                *calls]
            result = subprocess.run([sys.executable, str(Path(__file__).with_name('tutor_mcp.py')),
                '--context', str(context)], input='\n'.join(json.dumps(x) for x in frames)+'\n',
                capture_output=True, text=True, encoding='utf-8', timeout=5)
            self.assertEqual(result.returncode, 0, 'MCP server must run as a real stdio process')
            return [json.loads(x) for x in result.stdout.splitlines()]

    def test_initialize_list_and_selected_word_are_real_protocol_responses(self):
        out = self.exchange([
            {'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list', 'params': {}},
            {'jsonrpc': '2.0', 'id': 3, 'method': 'tools/call', 'params': {
                'name': 'read_selected_word', 'arguments': {}}}])
        self.assertEqual(out[0]['result']['protocolVersion'], '2025-06-18')
        self.assertEqual({t['name'] for t in out[1]['result']['tools']},
                         {'read_selected_word', 'create_practice_draft'})
        self.assertEqual(out[2]['result']['structuredContent']['spelling'], 'bottle')
        self.assertEqual(out[2]['result']['structuredContent']['revision'], 3)
        self.assertNotIn('owner', json.dumps(out))

    def test_draft_is_deterministic_and_does_not_award_learning_credit(self):
        request = {'jsonrpc': '2.0', 'id': 2, 'method': 'tools/call',
                   'params': {'name': 'create_practice_draft', 'arguments': {}}}
        out = self.exchange([request, {**request, 'id': 3}])
        a, b = [x['result']['structuredContent'] for x in out[1:]]
        self.assertEqual(a, b)
        self.assertEqual(a['wordId'], 'word-bottle')
        self.assertEqual(a['expectedAnswer'], 'bottle')
        self.assertFalse(a['awardsCredit'])

    def test_arbitrary_path_owner_or_shell_arguments_are_rejected(self):
        for arguments in [{'path': '../private'}, {'ownerId': 'other'}, {'command': 'whoami'}]:
            out = self.exchange([{'jsonrpc': '2.0', 'id': 2, 'method': 'tools/call',
                'params': {'name': 'read_selected_word', 'arguments': arguments}}])
            self.assertEqual(out[1]['error']['code'], -32602)

    def test_missing_selected_word_is_an_honest_tool_error(self):
        out = self.exchange([{'jsonrpc': '2.0', 'id': 2, 'method': 'tools/call',
            'params': {'name': 'read_selected_word', 'arguments': {}}}], {'selected': False})
        self.assertTrue(out[1]['result']['isError'])


if __name__ == '__main__':
    unittest.main()
