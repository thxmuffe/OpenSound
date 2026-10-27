"""Run native-window reload tests against a private copy of the compiled app."""
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import tempfile

from smoke import Node, ROOT, ERL, EBIN


def main():
    erlc = ERL.with_name('erlc.exe')
    tests = ROOT / 'test/parvi_reload_smoke.erl'
    build = (ROOT / '_build').resolve()
    with tempfile.TemporaryDirectory(prefix='ui-reload-test-', dir=build) as temp:
        assert Path(temp).resolve().is_relative_to(build)
        ebin = Path(temp) / 'ebin'
        shutil.copytree(EBIN, ebin)
        subprocess.run([str(erlc), '-Werror', '-o', str(ebin), str(tests)], check=True)
        peer = Node(8)
        try:
            assert peer.request()['node'] == peer.name
            env = {**os.environ, 'ERL_EPMD_ADDRESS': '127.0.0.1',
                   'PARVI_TEST_PEER': peer.name, 'PARVI_TEST_PEER_COOKIE': peer.cookie,
                   'PARVI_TEST_UI_SOURCE': str(ROOT / 'src/parvi_windows.erl')}
            subprocess.run([str(ERL), '-noshell', '-noinput',
                            '-name', f'parvi_windows_{os.getpid()}9@127.0.0.1',
                            '-setcookie', secrets.token_hex(24),
                            '-kernel', 'inet_dist_use_interface', '{127,0,0,1}',
                            '-pa', str(ebin), '-s', 'parvi_reload_smoke', 'main'],
                           check=True, timeout=60, env=env)
        finally:
            peer.close()


if __name__ == '__main__':
    main()
