"""Finite private mailbox between stdio MCP and the authenticated app bridge.

Only the owned ephemeral directory is used. The model never supplies paths,
owner identifiers, credentials or arbitrary app callbacks.
"""
import json
import re
import time
import uuid
from pathlib import Path

NAMES = {'list_menu_actions', 'execute_menu_action'}


def read(path):
    if path.stat().st_size > 48000:
        raise ValueError('oversized menu frame')
    value = json.loads(path.read_text(encoding='utf-8'))
    if not isinstance(value, dict):
        raise ValueError('invalid menu frame')
    return value


def write(path, value):
    data = json.dumps(value, ensure_ascii=False)
    if len(data.encode('utf-8')) > 48000:
        raise ValueError('oversized menu frame')
    temporary = path.with_suffix('.tmp')
    temporary.write_text(data, encoding='utf-8')
    temporary.replace(path)


def valid_arguments(name, args):
    if name == 'list_menu_actions':
        return args == {}
    return (name == 'execute_menu_action' and isinstance(args, dict)
            and set(args) in ({'id', 'revision'}, {'id', 'revision', 'values'})
            and isinstance(args.get('values', {}), dict)
            and len(args.get('values', {})) <= 8
            and all(isinstance(k, str) and re.fullmatch(r'[a-zA-Z][a-zA-Z0-9_]{0,39}', k)
                    and isinstance(v, str) and len(v) <= 4000
                    for k, v in args.get('values', {}).items())
            and isinstance(args['id'], str) and 0 < len(args['id']) <= 160
            and type(args['revision']) is int and args['revision'] >= 0)


class MenuChannel:
    def __init__(self, root):
        self.root = Path(root)
        self.root.mkdir(exist_ok=True)
        self.session = None
        self.delivered = {}

    def begin(self):
        self.end()
        self.session = uuid.uuid4().hex
        write(self.root / 'session.json', {'session': self.session})

    def end(self):
        self.session = None
        self.delivered.clear()
        (self.root / 'session.json').unlink(missing_ok=True)
        # Exact files beneath an owned ephemeral channel, never recursive.
        for path in self.root.iterdir():
            if re.fullmatch(r'[a-f0-9]{32}\.(request|result|tmp)', path.name):
                path.unlink(missing_ok=True)

    def next(self):
        if self.session is None:
            return None
        for path in sorted(self.root.glob('*.request')):
            if not re.fullmatch(r'[a-f0-9]{32}', path.stem):
                continue
            request = read(path)
            if (set(request) != {'session', 'requestId', 'name', 'arguments'}
                or request['session'] != self.session or request['requestId'] != path.stem
                or not valid_arguments(request['name'], request['arguments'])):
                raise ValueError('invalid menu request')
            if path.stem not in self.delivered:
                if len(self.delivered) >= 8:
                    raise ValueError('menu request limit')
                self.delivered[path.stem] = request
                return {k: v for k, v in request.items() if k != 'session'}
        return None

    def complete(self, request_id, result):
        request = self.delivered.get(request_id)
        if not self.session or not request or request['session'] != self.session:
            raise ValueError('stale menu result')
        path = self.root / (request_id + '.result')
        if path.exists():
            if read(path) != result:
                raise ValueError('conflicting menu result')
            return
        if not isinstance(result, dict):
            raise ValueError('invalid menu result')
        write(path, result)


def call(root, name, arguments, timeout=20):
    if not valid_arguments(name, arguments):
        raise ValueError('invalid menu arguments')
    root = Path(root)
    try:
        session = read(root / 'session.json')['session']
        request_id = uuid.uuid4().hex
        write(root / (request_id + '.request'), {
            'session': session, 'requestId': request_id, 'name': name,
            'arguments': arguments})
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if read(root / 'session.json').get('session') != session:
                return {'status': 'cancelled'}
            result = root / (request_id + '.result')
            if result.exists():
                return read(result)
            time.sleep(.03)
        return {'status': 'timeout'}
    except (OSError, ValueError, KeyError):
        return {'status': 'unavailable'}
