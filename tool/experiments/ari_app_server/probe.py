"""Run only the unauthenticated V1 diagnostic. Never login or start a turn."""
import argparse
import asyncio
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess

from adapter import Client, IsolatedHome

PINNED_SHA256 = 'bc343ba420dc2e2e9f59e6fc5e5bf0aae1cd8c771fc319665241fc9c0271fddb'
PINNED_VERSION = 'codex-cli 0.146.0'
SOURCE_SHA = 'c6dfb6d80c1494d3d085706b70776557ac20ec49'
SCHEMA_ROOT = Path(__file__).resolve().parents[3] / 'docs/development/ari/V1-R1-schema'


class ProbeFailure(Exception):
    pass


def sha256(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def require(value, message):
    if not value:
        raise ProbeFailure(message)


def anonymous_account(value):
    require(isinstance(value, dict) and 'account' in value
            and value['account'] is None and value.get('requiresOpenaiAuth') is True,
            'Expected explicitly unauthenticated account; aborting without logging payload')
    return {'account': None, 'requiresOpenaiAuth': True}


async def probe_session(client, expected_home=None):
    initialized = await client.request('initialize', {
        'clientInfo': {'name': 'ari_v1_diagnostic', 'version': '0.1.0'},
        'capabilities': {'experimentalApi': False}}, timeout=15)
    require(isinstance(initialized, dict) and all(
        isinstance(initialized.get(key), str)
        for key in ('userAgent', 'codexHome', 'platformFamily', 'platformOs')),
        'Unexpected initialize response shape')
    if expected_home is not None:
        require(Path(initialized['codexHome']).resolve() == expected_home.resolve(),
                'Server did not use the isolated home')
    await client.notify('initialized')
    before = anonymous_account(await client.request('account/read', {'refreshToken': False}))
    logout = await client.request('account/logout')
    require(logout == {}, 'Unexpected logout response')
    # Bounded event wait; do not let unrelated events extend the deadline.
    async with asyncio.timeout(5):
        while True:
            event = await client.next_event(5)
            if event['method'] == 'account/updated':
                params = event.get('params') or {}
                require('authMode' in params and params['authMode'] is None,
                        'Unexpected authenticated notification')
                break
    after = anonymous_account(await client.request('account/read', {'refreshToken': False}))
    return {'initialize': {'requiredFieldsPresent': True,
                           'isolatedHomeMatched': expected_home is not None},
            'beforeLogout': before, 'logout': {},
            'accountUpdated': {'authMode': None}, 'afterLogout': after}


def selected_requests(schema):
    """Retain four diagnostic methods and only their transitive definitions."""
    methods = {'initialize', 'account/read', 'account/logout', 'account/login/cancel'}
    selected = [v for v in schema['oneOf']
                if v['properties']['method']['enum'][0] in methods]
    require(len(selected) == len(methods), 'Required schema methods missing')
    needed = set()

    def visit(value):
        if isinstance(value, dict):
            if '$ref' in value:
                name = value['$ref'].split('/')[-1]
                if name not in needed:
                    needed.add(name)
                    visit(schema['definitions'][name])
            for key, item in value.items():
                if key != '$ref':
                    visit(item)
        elif isinstance(value, list):
            for item in value:
                visit(item)

    visit(selected)
    return dict(schema, oneOf=selected, definitions={
        k: v for k, v in schema['definitions'].items() if k in needed})


def run_cli(command, home):
    result = subprocess.run(command, cwd=home.cwd, env=home.env,
                            capture_output=True, text=True, encoding='utf-8', timeout=45,
                            creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
    require(result.returncode == 0, 'Isolated CLI command failed; raw output suppressed')
    return result.stdout


async def run(binary):
    binary = Path(binary).resolve(strict=True)
    require(sha256(binary) == PINNED_SHA256, 'Binary hash differs from reviewed 0.146.0 pin')
    home = IsolatedHome()
    client = None
    report = {'status': 'FAIL', 'kind': 'real-binary-unauthenticated',
              'sourceSha': SOURCE_SHA, 'timestampUtc': datetime.now(timezone.utc).isoformat(),
              'binary': {'version': PINNED_VERSION, 'sha256': PINNED_SHA256},
              'login': 'NOT_RUN', 'inference': 'NOT_RUN', 'remoteRevoke': 'NOT_RUN'}
    try:
        common = [str(binary), '-c', 'cli_auth_credentials_store="file"']
        require(run_cli(common + ['--version'], home).strip() == PINNED_VERSION,
                'Binary version mismatch')
        help_text = run_cli(common + ['app-server', '--help'], home)
        require('--stdio' in help_text and 'generate-json-schema' in help_text,
                'Required app-server tooling missing')
        report['helpSha256'] = hashlib.sha256(help_text.encode()).hexdigest()
        run_cli(common + ['app-server', 'generate-json-schema', '--out', str(home.root / 'schema')], home)
        generated = {p.name: p for p in (home.root / 'schema').rglob('*.json')}
        pins = {}
        for pin in sorted(SCHEMA_ROOT.glob('*.json')):
            current = json.loads(generated[pin.name].read_text(encoding='utf-8'))
            if pin.name == 'ClientRequest.json':
                current = selected_requests(current)
            require(current == json.loads(pin.read_text(encoding='utf-8')), 'Schema pin changed')
            pins[pin.name] = sha256(pin)
        require(len(pins) == 8, 'Expected eight schema pins')
        report['schemaPins'] = pins
        require(not (home.root / 'home' / 'auth.json').exists(), 'Unexpected auth file before startup')
        require(not list(home.cwd.iterdir()), 'Child cwd is not empty before startup')
        client = await Client.start(common + ['app-server', '--stdio'], home.cwd, home.env)
        report['protocol'] = await probe_session(client, home.root / 'home')
        report['isolation'] = {
            'environmentKeys': sorted(home.env), 'credentialStore': 'file',
            'authFileAbsentBefore': True,
            'authFileAbsentAfter': not (home.root / 'home' / 'auth.json').exists(),
            'cwdEmptyBefore': True, 'parentEnvironmentMutated': False,
            'boundary': 'configuration isolation; not an OS sandbox or network trace'}
        require(report['isolation']['authFileAbsentAfter'], 'Unexpected auth file after logout')
        report['status'] = 'PASS'
    finally:
        if client is not None:
            await client.close()
            report['childReaped'] = client.process.returncode is not None
            report['childExitCode'] = client.process.returncode
        home.close()
        report['temporaryRootRemoved'] = not home.root.exists()
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', required=True)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    # Refuse accidental overwrite of accepted evidence; caller chooses a fresh file.
    require(not args.output.exists(), 'Output exists; choose a new evidence filename')
    try:
        report = asyncio.run(run(args.binary))
    except Exception as error:
        report = {'status': 'FAIL', 'errorType': type(error).__name__,
                  'detail': 'Raw exception and protocol data suppressed; no PASS recorded'}
    with args.output.open('x', encoding='utf-8') as stream:
        json.dump(report, stream, indent=2)
        stream.write('\n')
    print(json.dumps({'status': report['status'], 'output': str(args.output)}))
    return 0 if report['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
