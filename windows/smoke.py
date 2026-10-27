"""Exercise the bundled Windows BEAM, shared bridge and Reception desk on loopback."""
import json
import os
from pathlib import Path
import queue
import secrets
import socket
import subprocess
import threading
import time
import urllib.request

ROOT = Path(__file__).resolve().parent
ERL = ROOT / '_build/Parvi/runtime/bin/erl.exe'
EBIN = ROOT / '_build/Parvi/ebin'
BROKER = ROOT.parent / 'broker/_build/windows/lib/parvi_broker/ebin'


class Node:
    def __init__(self, suffix):
        self.name = f'parvi_windows_{os.getpid()}{suffix}@127.0.0.1'
        self.cookie = secrets.token_hex(24)
        self.lines = queue.Queue()
        self.process = subprocess.Popen([
            str(ERL), '-noshell', '-name', self.name, '-setcookie', self.cookie,
            '-kernel', 'inet_dist_use_interface', '{127,0,0,1}',
            '-pa', str(EBIN), '-s', 'parvi_bridge', 'main'],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            text=True, encoding='utf-8', env={**os.environ, 'ERL_EPMD_ADDRESS': '127.0.0.1'})
        threading.Thread(target=self.read, daemon=True).start()

    def read(self):
        for line in self.process.stdout:
            try:
                self.lines.put(json.loads(line))
            except json.JSONDecodeError:
                pass

    def request(self, method='snapshot', **args):
        self.process.stdin.write(json.dumps(dict(method=method, **args)) + '\n')
        self.process.stdin.flush()
        return self.lines.get(timeout=10)

    def close(self):
        self.process.stdin.close()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()


def await_snapshot(node, predicate):
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        reply = node.request()
        if predicate(reply):
            return reply
        time.sleep(.1)
    raise AssertionError('Timed out waiting for peer/history update')


def main():
    if not BROKER.exists():
        raise SystemExit('Run broker/run.ps1 once to compile the Reception desk first.')
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    url = f'http://127.0.0.1:{port}'
    broker = subprocess.Popen([
        str(ERL), '-noshell', '-noinput', '-pa', str(BROKER), '-eval',
        f'application:load(parvi_broker), application:set_env(parvi_broker, port, {port}), '
        '{ok, _} = application:ensure_all_started(parvi_broker), receive stop -> ok end.'
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    nodes = []
    try:
        for _ in range(80):
            try:
                with urllib.request.urlopen(url + '/api/nodes', timeout=.5):
                    break
            except OSError:
                time.sleep(.1)
        else:
            raise AssertionError('Reception desk did not start')
        a, b = Node(1), Node(2)
        nodes.extend([a, b])
        assert a.request()['node'] == a.name
        assert b.request()['node'] == b.name
        assert a.request('discover', url=url)['error'] is None
        assert a.name in b.request('discover', url=url)['known_nodes']
        assert b.name in a.request('discover', url=url)['known_nodes']
        assert a.request('connect', node='parvi_windows_1@192.168.1.5', cookie='test')['error']
        assert a.request('connect', node=b.name, cookie=b.cookie)['error'] is None
        await_snapshot(a, lambda r: b.name in r['peers'])
        await_snapshot(b, lambda r: a.name in r['peers'])
        text = 'Hello from Windows: Hei parvi! 🐦 <>&'
        assert a.request('send', text=text)['error'] is None
        await_snapshot(b, lambda r: any(m['text'] == text for m in r['messages']))
        assert b.request('send', text='Reply from the second BEAM')['error'] is None
        await_snapshot(a, lambda r: any(m['text'] == 'Reply from the second BEAM' for m in r['messages']))
        assert a.request('send', text='x' * 4097)['error']
        b.close()
        nodes.remove(b)
        await_snapshot(a, lambda r: b.name not in r['peers'])
        print('PASS: real Windows nodes, directory discovery, authenticated connection, UTF-8 two-way chat, validation, departure')
    finally:
        for node in nodes:
            node.close()
        broker.terminate()
        broker.wait(timeout=5)


if __name__ == '__main__':
    main()
