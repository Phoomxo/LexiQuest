"""Private stdio MCP tools over one explicitly selected vocabulary snapshot."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
from menu_channel import call as menu_call, valid_arguments, NAMES

TOOLS = [
    {'name': name, 'description': description,
     'inputSchema': {'type': 'object', 'properties': {}, 'additionalProperties': False},
     'annotations': {'readOnlyHint': True, 'destructiveHint': False,
                     'idempotentHint': True, 'openWorldHint': False}}
    for name, description in [
        ('read_selected_word', 'Read the word explicitly selected in LexiQuest, including its meaning and revision. Use before explaining that word.'),
        ('create_practice_draft', 'Create a deterministic, unscored spelling-practice draft for the selected word. Does not save progress or award points.')]]

MENU_TOOLS = [
    {'name': 'list_menu_actions', 'description': 'Read currently available LexiQuest menu actions and their revision. Only advertised actions may be invoked. Unavailable and covered screens are excluded.',
     'inputSchema': {'type': 'object', 'properties': {}, 'additionalProperties': False},
     'annotations': {'readOnlyHint': True, 'openWorldHint': False}},
    {'name': 'execute_menu_action', 'description': 'Invoke one real app control from the latest list. An invoked result only confirms the callback ran; it does not certify a save, lesson completion or score. Confirmations remain in the app for the learner.',
     'inputSchema': {'type': 'object', 'properties': {
         'id': {'type': 'string', 'maxLength': 160},
         'revision': {'type': 'integer', 'minimum': 0}},
         'required': ['id', 'revision'], 'additionalProperties': False},
     'annotations': {'readOnlyHint': False, 'destructiveHint': True,
                     'idempotentHint': False, 'openWorldHint': False}}]


def validate_word(word):
    fields = {'id': 200, 'spelling': 200, 'meaning': 2000, 'partOfSpeech': 80}
    if not isinstance(word, dict) or set(word) != {*fields, 'revision'}:
        raise ValueError('invalid selected word')
    for key, limit in fields.items():
        if not isinstance(word[key], str) or not word[key].strip() or len(word[key]) > limit:
            raise ValueError('invalid selected word')
    if type(word['revision']) is not int or word['revision'] < 1:
        raise ValueError('invalid revision')
    return word


def tool_result(context, name):
    try:
        if context.stat().st_size > 12000:
            raise ValueError()
        word = validate_word(json.loads(context.read_text(encoding='utf-8')))
    except (OSError, ValueError, TypeError):
        return {'content': [{'type': 'text', 'text': 'No valid selected vocabulary. Ask the learner to select a word.'}], 'isError': True}
    data = word
    if name == 'create_practice_draft':
        identity = json.dumps(word, sort_keys=True, ensure_ascii=False).encode()
        data = {'draftId': hashlib.sha256(identity).hexdigest()[:24],
                'wordId': word['id'], 'revision': word['revision'],
                'prompt': 'พิมพ์คำภาษาอังกฤษที่หมายถึง: ' + word['meaning'],
                'expectedAnswer': word['spelling'], 'awardsCredit': False}
    return {'content': [{'type': 'text', 'text': json.dumps(data, ensure_ascii=False)}],
            'structuredContent': data, 'isError': False}


def serve(context, menu=None):
    initialized = False
    for line in sys.stdin:
        request_id = None
        try:
            if len(line) > 16384:
                raise ValueError()
            frame = json.loads(line)
            if not isinstance(frame, dict) or frame.get('jsonrpc') != '2.0':
                raise ValueError()
            request_id = frame.get('id')
            method, params = frame.get('method'), frame.get('params', {})
            if request_id is None:
                if method == 'notifications/initialized':
                    initialized = True
                continue
            if method == 'initialize':
                result = {'protocolVersion': '2025-06-18', 'capabilities': {'tools': {}},
                          'serverInfo': {'name': 'lexiquest-selected-word', 'version': '0.1.0'}}
            elif not initialized:
                raise ValueError()
            elif method == 'ping':
                result = {}
            elif method == 'tools/list':
                result = {'tools': TOOLS + (MENU_TOOLS if menu else [])}
            elif (method == 'tools/call' and menu and isinstance(params, dict)
                  and params.get('name') in NAMES
                  and valid_arguments(params['name'], params.get('arguments', {}))):
                data = menu_call(menu, params['name'], params.get('arguments', {}))
                result = {'content': [{'type': 'text', 'text': json.dumps(data, ensure_ascii=False)}],
                          'structuredContent': data,
                          'isError': data.get('status') not in ('invoked', 'available')}
            elif (method == 'tools/call' and isinstance(params, dict)
                  and params.get('name') in {t['name'] for t in TOOLS}
                  and params.get('arguments', {}) == {}):
                result = tool_result(context, params['name'])
            else:
                raise ValueError()
            response = {'jsonrpc': '2.0', 'id': request_id, 'result': result}
        except (ValueError, TypeError, KeyError):
            response = {'jsonrpc': '2.0', 'id': request_id,
                        'error': {'code': -32602, 'message': 'Unsupported or invalid request'}}
        print(json.dumps(response, ensure_ascii=False), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--context', required=True, type=Path)
    parser.add_argument('--menu', type=Path)
    args = parser.parse_args()
    sys.stdin.reconfigure(encoding='utf-8')
    sys.stdout.reconfigure(encoding='utf-8')
    serve(args.context, args.menu)
