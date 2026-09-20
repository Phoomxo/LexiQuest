"""Synthetic stdio peer only; never starts Codex or makes network requests."""
import json
import os
import sys
import time

held = None
server_request_parent = None
ignore_eof = False
late_on_exit = False


def send(value):
    print(json.dumps(value), flush=True)


for line in sys.stdin:
    msg = json.loads(line)
    method = msg.get('method')
    rid = msg.get('id')
    if method == 'hold':
        held = msg
        send({'method': 'held', 'params': {}})
        continue
    if method == 'release':
        send({'id': rid, 'result': 'second'})
        send({'id': held['id'], 'result': held['params']['value']})
        send({'method': 'released', 'params': {}})
        continue
    if method == 'error':
        send({'id': rid, 'error': {'code': -32000, 'message': 'secret'}})
        continue
    if method == 'die':
        sys.exit(7)
    if method == 'malformed':
        print('not-json', flush=True)
        continue
    if method == 'invalid-envelope':
        send({'id': rid, 'result': 'bad', 'error': {'code': -1}})
        continue
    if method == 'ignore-eof':
        ignore_eof = True
    if method == 'late-on-exit':
        late_on_exit = True
    if method == 'queue-login-event':
        send({'method': 'account/login/completed', 'params': {'loginId': 'fake-login', 'success': True}})
        result = {}
    elif method == 'account/login/cancel':
        assert msg['params'] == {'loginId': 'fake-login'}
        send({'method': 'account/login/completed', 'params': {'loginId': 'fake-login', 'success': True}})
        send({'method': 'after-cancel', 'params': {}})
        result = {'status': 'canceled'}
    elif method == 'environment':
        result = {'cwd': os.getcwd(), 'env': dict(os.environ), 'files': os.listdir('.')}
    elif method == 'server-request':
        server_request_parent = rid
        send({'id': 'server-1', 'method': 'account/chatgptAuthTokens/refresh', 'params': {}})
        continue
    elif rid == 'server-1':
        send({'id': server_request_parent, 'result': msg['error']['code']})
        continue
    else:
        result = 'pong'
    send({'id': rid, 'result': result})

if late_on_exit:
    send({'method': 'account/login/completed', 'params': {'loginId': 'late-session', 'success': True}})
if ignore_eof:
    time.sleep(30)
