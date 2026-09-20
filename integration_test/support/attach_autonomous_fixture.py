"""Attach to an already installed isolated Vivo integration fixture over USB.

Build with AUTONOMOUS_DEVICE_VIEWPORT=true and ariLocalTest=true first.
Never run a second UI automation client during the integration test.
"""

import argparse
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
from urllib.parse import urlparse


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--log', type=Path, required=True)
    parser.add_argument('--adb', default=shutil.which('adb'))
    parser.add_argument('--flutter', default=shutil.which('flutter'))
    args = parser.parse_args()
    if not args.adb or not args.flutter:
        parser.error('Supply --adb and --flutter or add both executables to PATH')
    if args.log.exists():
        parser.error('Choose a new log path; previous evidence must be preserved')
    adb = [args.adb, '-s', args.serial]
    receipt = ['shell', 'run-as', 'com.lexiquest.app.ariTest',
               'cat', 'code_cache/autonomous-vm-service.txt']
    for _ in range(30):
        result = subprocess.run(adb + receipt, capture_output=True, text=True)
        if result.returncode == 0:
            break
        time.sleep(0.3)
    else:
        raise RuntimeError('Fixture did not publish its private endpoint')
    uri = urlparse(result.stdout.strip())
    if not (uri.scheme == 'http' and uri.hostname in ('127.0.0.1', 'localhost', '::1')
            and uri.port and uri.path not in ('', '/')):
        raise RuntimeError('Require an authenticated loopback VM endpoint')
    port = subprocess.run(adb + ['forward', 'tcp:0', f'tcp:{uri.port}'],
                          capture_output=True, text=True, check=True).stdout.strip()
    if not port.isdigit():
        raise RuntimeError('ADB did not return the owned forwarding port')
    try:
        args.log.parent.mkdir(parents=True, exist_ok=True)
        command = [args.flutter, 'drive', '-d', args.serial,
                   '--driver=test_driver/autonomous_core_driver.dart',
                   f'--use-existing-app=http://127.0.0.1:{port}{uri.path}',
                   '--no-pub', '--no-dds']
        print('Attaching fixture through an authenticated owned USB forward', flush=True)
        with args.log.open('x', encoding='utf-8') as output:
            process = subprocess.Popen(command, stdout=subprocess.PIPE,
                                       stderr=subprocess.STDOUT, text=True,
                                       encoding='utf-8', errors='replace')
            for line in process.stdout:
                line = re.sub(r'(?:http|ws)s?://[^\s]+', '[local-service-url]', line)
                output.write(line)
                output.flush()
                if 'flutter (' in line or not re.match(r'^[VDIW]/', line):
                    print(line, end='', flush=True)
            code = process.wait()
    finally:
        subprocess.run(adb + ['forward', '--remove', f'tcp:{port}'], capture_output=True)
        subprocess.run(adb + ['shell', 'run-as', 'com.lexiquest.app.ariTest',
                             'rm', '-f', 'code_cache/autonomous-vm-service.txt'],
                       capture_output=True)
    print('Fixture driver exit', code, flush=True)
    return code


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    sys.exit(main())
