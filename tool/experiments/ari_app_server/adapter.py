"""V1 stdio diagnostic, not a production gateway. Python standard library only.

One Client owns one child and one session. Local request cancellation only stops
waiting; cancel_login is the schema-defined remote login cancellation operation.
No generic JSON-RPC cancellation method is invented here.
"""
import asyncio
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


class RpcError(Exception):
    def __init__(self, code):
        self.code = code
        super().__init__(f'App Server RPC error ({code})')


class ProtocolError(Exception):
    pass


class IsolatedHome:
    """Allowlisted child env; never read the caller's Codex home or auth store.

    This is configuration isolation, not an OS security boundary against a
    malicious binary. The diagnostic uses a trusted, hash-pinned local binary.
    """
    def __init__(self, parent=None):
        parent = os.environ if parent is None else parent
        self.root = Path(tempfile.mkdtemp(prefix='ari-app-server-')).resolve()
        self._created_root = self.root
        self._temp_parent = self.root.parent
        self._closed = False
        for name in ('home', 'cwd', 'tmp', 'appdata', 'local'):
            (self.root / name).mkdir()
        self.cwd = self.root / 'cwd'
        self.env = {k: v for k, v in parent.items()
                    if k.upper() in {'SYSTEMROOT', 'WINDIR', 'COMSPEC', 'SYSTEMDRIVE'}}
        for key, directory in {'CODEX_HOME': 'home', 'HOME': 'home',
                               'USERPROFILE': 'home', 'APPDATA': 'appdata',
                               'LOCALAPPDATA': 'local', 'TEMP': 'tmp', 'TMP': 'tmp',
                               'XDG_CONFIG_HOME': 'home', 'XDG_CACHE_HOME': 'tmp'}.items():
            self.env[key] = str(self.root / directory)
        (self.root / 'home' / 'config.toml').write_text(
            'cli_auth_credentials_store = "file"\n'
            '[analytics]\nenabled = false\n', encoding='utf-8')

    def close(self):
        if self._closed:
            return
        target = self.root.resolve()
        if (target != self._created_root or target.parent != self._temp_parent
                or not target.name.startswith('ari-app-server-')
                or self.root.is_symlink() or self.root.is_junction()):
            raise ValueError('Refusing cleanup outside owned temporary root')
        # Reject links/junctions inside the owned root before recursive deletion.
        for base, dirs, files in os.walk(target, followlinks=False):
            for name in dirs + files:
                path = Path(base) / name
                if path.is_symlink() or path.is_junction() or not path.resolve().is_relative_to(target):
                    raise ValueError('Refusing cleanup of redirected temporary entry')
        shutil.rmtree(target)
        self._closed = True


class Client:
    def __init__(self, process):
        self.process = process
        self._pending = {}
        self._sequence = 0
        self._events = asyncio.Queue(maxsize=256)
        self._cancelled_logins = set()
        self._terminal = None
        self._closed = False
        self._writer_lock = asyncio.Lock()
        self._reader = asyncio.create_task(self._read())

    @classmethod
    async def start(cls, command, cwd, env):
        process = await asyncio.create_subprocess_exec(
            *command, cwd=cwd, env=env, stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL,
            limit=1024 * 1024,
            creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
        return cls(process)

    async def _send(self, message):
        async with self._writer_lock:
            if self._terminal:
                raise self._terminal
            try:
                self.process.stdin.write((json.dumps(message) + '\n').encode('utf-8'))
                await self.process.stdin.drain()
            except (BrokenPipeError, ConnectionError):
                raise EOFError('App Server input closed') from None

    async def request(self, method, params=None, timeout=5):
        if timeout <= 0:
            raise ValueError('timeout must be positive')
        if self._terminal:
            raise self._terminal
        self._sequence += 1
        rid = self._sequence
        future = asyncio.get_running_loop().create_future()
        self._pending[rid] = future
        message = {'id': rid, 'method': method}
        if params is not None:
            message['params'] = params
        try:
            # Includes writing/drain in the deadline, not just the response wait.
            async with asyncio.timeout(timeout):
                await self._send(message)
                return await future
        finally:
            self._pending.pop(rid, None)
            if not future.done():
                future.cancel()

    async def notify(self, method, params=None, timeout=5):
        message = {'method': method}
        if params is not None:
            message['params'] = params
        async with asyncio.timeout(timeout):
            await self._send(message)

    async def cancel_login(self, login_id, timeout=5):
        # Tombstone first: queued/in-flight completion must not restore UI state.
        self._cancelled_logins.add(login_id)
        return await self.request('account/login/cancel', {'loginId': login_id}, timeout)

    def _suppressed(self, event):
        params = event.get('params') or {}
        return params.get('loginId') in self._cancelled_logins

    async def next_event(self, timeout=5):
        async with asyncio.timeout(timeout):
            while True:
                if self._terminal:
                    raise self._terminal
                event = await self._events.get()
                if self._terminal:
                    raise self._terminal
                if not self._suppressed(event):
                    return event

    def _finish(self, error):
        if self._terminal:
            return
        self._terminal = error
        for future in self._pending.values():
            if not future.done():
                future.set_exception(error)
        while not self._events.empty():
            self._events.get_nowait()
        self._events.put_nowait(None)  # wake the single event consumer

    async def _read(self):
        try:
            while line := await self.process.stdout.readline():
                try:
                    message = json.loads(line)
                    if not isinstance(message, dict):
                        raise ValueError()
                    if 'method' in message:
                        if not isinstance(message['method'], str) or not isinstance(message.get('params', {}), (dict, type(None))):
                            raise ValueError()
                        if 'id' in message:
                            # No credential-refresh/approval handlers in this diagnostic.
                            await self._send({'id': message['id'], 'error': {
                                'code': -32601, 'message': 'Unsupported diagnostic server request'}})
                        elif not self._suppressed(message):
                            self._events.put_nowait(message)
                    else:
                        rid = message['id']
                        if type(rid) not in (int, str) or ('result' in message) == ('error' in message):
                            raise ValueError()
                        if 'error' in message and (not isinstance(message['error'], dict)
                                or type(message['error'].get('code')) is not int):
                            raise ValueError()
                        future = self._pending.get(rid)
                        if future is not None and not future.done():
                            if 'error' in message:
                                future.set_exception(RpcError(message['error']['code']))
                            else:
                                future.set_result(message['result'])
                except (ValueError, KeyError, TypeError, asyncio.QueueFull):
                    raise ProtocolError('Invalid or excessive App Server frames') from None
            self._finish(EOFError('App Server stdout closed'))
        except asyncio.CancelledError:
            raise
        except Exception as error:
            self._finish(error if isinstance(error, (ProtocolError, EOFError))
                         else ProtocolError('App Server stream failed'))

    async def close(self):
        if self._closed:
            return
        self._finish(EOFError('App Server session closed'))
        self.process.stdin.close()
        try:
            await asyncio.wait_for(self.process.wait(), 1)
        except TimeoutError:
            if self.process.returncode is None:
                self.process.terminate()
            try:
                await asyncio.wait_for(self.process.wait(), 2)
            except TimeoutError:
                if self.process.returncode is None:
                    self.process.kill()
                await asyncio.wait_for(self.process.wait(), 2)
        finally:
            self._reader.cancel()
            await asyncio.gather(self._reader, return_exceptions=True)
        self._closed = True
