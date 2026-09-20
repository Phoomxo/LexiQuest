"""Controlled developer login bridge, never a production or inference gateway.

Loopback + random bearer capability, single session, 15 minute maximum lifetime.
No logs, provider payload dumps, API keys, existing auth, or public listeners.
Credentials live only in the isolated App Server process (ephemeral store).
"""
import argparse
import asyncio
import hmac
import json
import re
import secrets
import subprocess
from pathlib import Path
from adapter import Client, IsolatedHome
from probe import sha256, PINNED_SHA256


class BridgeError(Exception):
    pass


class LoginSession:
    def __init__(self, start):
        self.start = start
        self.client = None
        self.cleanup = None
        self.login_id = None
        self.lock = asyncio.Lock()

    async def login(self):
        async with self.lock:
            await self._close()
            try:
                self.client, self.cleanup = await self.start()
                result = await self.client.request('account/login/start',
                    {'type': 'chatgptDeviceCode'}, timeout=30)
                if (result.get('type') != 'chatgptDeviceCode'
                        or result.get('verificationUrl') != 'https://auth.openai.com/codex/device'
                        or not isinstance(result.get('loginId'), str)
                        or not re.fullmatch(r'[A-Z0-9-]{4,32}', result.get('userCode', ''))):
                    raise BridgeError('unsupported_login')
                self.login_id = result['loginId']
                return {key: result[key] for key in ('verificationUrl', 'userCode')}
            except BaseException as error:
                await self._close()
                if isinstance(error, asyncio.CancelledError): raise
                raise BridgeError('login_unavailable') from None

    async def status(self):
        async with self.lock:
            authenticated = False
            if self.client:
                result = await self.client.request('account/read', {'refreshToken': False})
                account = result.get('account')
                authenticated = isinstance(account, dict) and account.get('type') == 'chatgpt'
            return {'authenticated': authenticated, 'inferenceEnabled': False}

    async def _close(self):
        client, cleanup, login_id = self.client, self.cleanup, self.login_id
        self.client = self.cleanup = self.login_id = None
        if client:
            try:
                if login_id:
                    await client.cancel_login(login_id)
                await client.request('account/logout')
            except Exception:
                pass  # Child termination clears in-memory credentials even on logout failure.
            finally:
                await client.close()
        if cleanup:
            cleanup()

    async def close(self):
        async with self.lock:
            await self._close()


class Bridge:
    def __init__(self, session, token):
        if len(token) < 40:
            raise ValueError('Capability too short')
        self.session, self.token = session, token
        self.busy = False

    async def dispatch(self, path, payload, token):
        if not hmac.compare_digest(token, self.token):
            raise BridgeError('unauthorized')
        if payload != {}:
            raise BridgeError('invalid_request')
        if path == '/login': return await self.session.login()
        if path == '/status': return await self.session.status()
        if path == '/disconnect':
            await self.session.close()
            return {'authenticated': False, 'inferenceEnabled': False}
        raise BridgeError('unsupported_operation')

    async def handle(self, reader, writer):
        # No access log and no exception payload forwarding.
        response, code = {'error': 'unavailable'}, 503
        admitted = False
        try:
            async with asyncio.timeout(40):
                header = await reader.readuntil(b'\r\n\r\n')
                if len(header) > 4096 or self.busy:
                    raise BridgeError('invalid_request')
                lines = header.decode('ascii').split('\r\n')
                verb, path, version = lines[0].split(' ')
                fields = {}
                for line in lines[1:]:
                    if line:
                        key, value = line.split(':', 1)
                        key = key.lower()
                        if key in fields: raise BridgeError('invalid_request')
                        fields[key] = value.strip()
                if (verb != 'POST' or version != 'HTTP/1.1' or 'origin' in fields
                        or 'transfer-encoding' in fields
                        or fields.get('content-length') != '2'
                        or fields.get('content-type', '').split(';')[0].strip() != 'application/json'
                        or fields.get('host') not in ('127.0.0.1:8765', 'localhost:8765')):
                    raise BridgeError('invalid_request')
                payload = json.loads(await reader.readexactly(2))
                token = fields.get('authorization', '').removeprefix('Bearer ')
                self.busy = admitted = True
                response = await self.dispatch(path, payload, token)
                code = 200
        except BridgeError as error:
            response, code = {'error': str(error)}, 403
        except Exception:
            pass
        finally:
            if admitted: self.busy = False
            data = json.dumps(response).encode()
            try:
                writer.write((f'HTTP/1.1 {code} Response\r\nContent-Type: application/json\r\n'
                    f'Content-Length: {len(data)}\r\nCache-Control: no-store\r\n'
                    'Connection: close\r\n\r\n').encode() + data)
                await asyncio.wait_for(writer.drain(), 2)
            except Exception:
                pass
            writer.close()
            await writer.wait_closed()


async def start_isolated(binary):
    if sha256(binary) != PINNED_SHA256:
        raise BridgeError('binary_pin_mismatch')
    home = IsolatedHome()
    client = None
    try:
        # Override the diagnostic file-store default before launching any child.
        (home.root / 'home/config.toml').write_text(
            'cli_auth_credentials_store = "ephemeral"\nforced_login_method = "chatgpt"\n'
            '[analytics]\nenabled = false\n', encoding='utf-8')
        client = await Client.start([str(binary), 'app-server', '--stdio'], home.cwd, home.env)
        result = await client.request('initialize', {
            'clientInfo': {'name': 'ari_local_login_test', 'version': '0.1.0'},
            'capabilities': {'experimentalApi': False}}, timeout=15)
        if Path(result['codexHome']).resolve() != (home.root / 'home').resolve():
            raise BridgeError('isolation_failed')
        await client.notify('initialized')
        result = await client.request('account/read', {'refreshToken': False})
        if result.get('account') is not None:
            raise BridgeError('unexpected_existing_account')
        return client, home.close
    except BaseException:
        if client: await client.close()
        home.close()
        raise


async def run(args, session_factory=LoginSession, start_factory=start_isolated, bridge_factory=Bridge):
    token = secrets.token_urlsafe(32)
    session = session_factory(lambda: start_factory(args.binary))
    bridge = bridge_factory(session, token)
    # Provision only the designated debug app's private sandbox, never argv/logs.
    # Device identity is checked independently before this explicit invocation.
    config = json.dumps({'token': token}).encode()
    adb = [args.adb, '-s', args.serial]
    manufacturer = subprocess.run(adb + ['shell', 'getprop', 'ro.product.manufacturer'],
        capture_output=True, text=True, timeout=15)
    if manufacturer.returncode or manufacturer.stdout.strip().lower() != 'vivo':
        raise BridgeError('designated_vivo_unavailable')
    mappings = subprocess.run(adb + ['reverse', '--list'], capture_output=True,
        text=True, timeout=15)
    if mappings.returncode or 'tcp:8765' in mappings.stdout:
        raise BridgeError('reverse_port_already_owned')
    # Bind before handing the capability to the app; an occupied port is fatal.
    server = await asyncio.start_server(bridge.handle, '127.0.0.1', 8765, limit=4096)
    provisioned = reversed_port = False
    try:
        async with server:
            subprocess.run(adb + ['shell', 'run-as', 'com.lexiquest.app.ariTest',
                'mkdir', '-p', 'files'], check=True,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)
            provision = subprocess.run(adb + ['shell', 'run-as', 'com.lexiquest.app.ariTest',
                'tee', 'files/ari-bridge.json'], input=config,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)
            provisioned = True
            if provision.returncode != 0: raise BridgeError('provision_failed')
            subprocess.run(adb + ['reverse', 'tcp:8765', 'tcp:8765'], check=True,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)
            reversed_port = True
            print('Local private-login bridge ready; expires in 15 minutes. No credentials logged.', flush=True)
            await asyncio.sleep(900)
    finally:
        await session.close()
        if reversed_port:
            subprocess.run(adb + ['reverse', '--remove', 'tcp:8765'],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)
        if provisioned:
            subprocess.run(adb + ['shell', 'run-as', 'com.lexiquest.app.ariTest',
                'rm', '-f', 'files/ari-bridge.json'],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--binary', type=Path, required=True)
    parser.add_argument('--adb', required=True)
    parser.add_argument('--serial', required=True)
    arguments = parser.parse_args()
    try:
        asyncio.run(run(arguments))
    except KeyboardInterrupt:
        pass
    except Exception:
        raise SystemExit('Bridge stopped; diagnostic details suppressed to protect login data.')
