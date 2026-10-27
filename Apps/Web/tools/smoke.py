"""Real HTTP directory + two app runtimes; no third-party Python packages."""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "Apps/macOS/tools"))
from smoke import Instance, await_state

with socket.socket() as probe:
    probe.bind(("127.0.0.1", 0))
    port = probe.getsockname()[1]
base = f"http://127.0.0.1:{port}"
env = dict(os.environ, PARVI_BROKER_BIND="127.0.0.1", PARVI_BROKER_PORT=str(port))


def start():
    process = subprocess.Popen(["bash", "Apps/Web/run.sh"], cwd=ROOT, env=env,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(150):
        try:
            if call()[0] == 200:
                return process
        except (OSError, urllib.error.URLError):
            pass
        if process.poll() is not None:
            raise RuntimeError("Test broker failed to start")
        time.sleep(0.05)
    process.terminate()
    process.wait(timeout=5)
    raise TimeoutError("Test broker startup")


def call(body=None, method=None, content_type="application/json", path="/api/nodes"):
    request = urllib.request.Request(base + path, data=body, method=method,
                                     headers={"Content-Type": content_type})
    try:
        response = urllib.request.urlopen(request, timeout=3)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        return response.status, response.read()


broker = start()
first = second = None
try:
    assert json.loads(call()[1]) == {"node_ids": []}
    assert call(path="/")[0] == 200
    assert call(path="/qrcode.js")[0] == 200
    assert call(b"not json")[0] == 400
    assert call(b'{}')[0] == 400
    assert call(b'{"node_id":"x@host"}', content_type="text/plain")[0] == 415
    assert call(method="DELETE")[0] == 405
    assert call(b"x" * 2048)[0] == 413
    first, second = Instance(1), Instance(2)
    initial = first.request("discover", url=base)
    assert initial["error"] is None, initial
    discovered = second.request("discover", url=base)
    assert discovered["error"] is None
    assert discovered["known_nodes"] == [first.node]
    refreshed = first.request("discover", url=base)
    assert refreshed["known_nodes"] == [second.node]
    assert len(json.loads(call()[1])["node_ids"]) == 2  # refresh deduplicates
    assert first.request("connect", node=second.node, cookie=second.cookie)["error"] is None
    await_state(first, lambda s: second.node in s["peers"])
    first.request("send", text="Found through the local directory")
    await_state(second, lambda s: any(m["text"] == "Found through the local directory" for m in s["messages"]))
    second.request("send", text="Handshake and reply confirmed")
    await_state(first, lambda s: any(m["text"] == "Handshake and reply confirmed" for m in s["messages"]))
    broker.terminate()
    broker.wait(timeout=5)
    broker = start()
    assert json.loads(call()[1])["node_ids"] == []
    print("PASS: HTTP API, validation, duplicate registration, app discovery, Erlang handshake, two-way chat, restart clears names")
finally:
    for instance in (first, second):
        if instance is not None:
            instance.close()
    broker.terminate()
    broker.wait(timeout=5)
