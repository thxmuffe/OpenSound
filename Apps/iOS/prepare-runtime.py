#!/usr/bin/env python3
"""Prepare a pinned iOS BEAM runtime and the shared Erlang application."""
import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
HASHES = {
    'device': '437475e8abb721f3ffbbfe6f17ddb495e8bddd13503eaee87aea5e2c14e5dd1d',
    'sim': 'a6066a1cce2391f78e1cbf45f89f758f78e42cf8f8fda7363660940f4a7b6755',
}
parser = argparse.ArgumentParser()
parser.add_argument('--target', choices=HASHES, default='device')
args = parser.parse_args()
target = args.target
archive = ROOT / f'builds/intermediates/iOS/downloads/otp-ios-{target}-d199a49a.tar.gz'
archive.parent.mkdir(parents=True, exist_ok=True)
if not archive.exists():
    url = f'https://github.com/GenericJam/mob/releases/download/otp-d199a49a/{archive.name}'
    print('Downloading', url, flush=True)
    urllib.request.urlretrieve(url, archive)
assert hashlib.sha256(archive.read_bytes()).hexdigest() == HASHES[target], 'Runtime SHA-256 mismatch'
otp = ROOT / f'builds/intermediates/iOS/otp-{target}'
if not (otp / 'erts-17.1.1/lib/libbeam.a').exists():
    otp.mkdir(parents=True, exist_ok=True)
    # The release tarball contains one temporary staging directory at its root.
    subprocess.run(['tar', '-xzf', str(archive), '--strip-components', '1', '-C', str(otp)], check=True)
# Same OTP version/compiler as the phone runtime; do not copy host OTP libraries.
version = subprocess.check_output(['erl', '-noshell', '-eval',
    'io:put_chars(erlang:system_info(version)), halt().'], text=True)
assert version == '17.1.1', f'Expected ERTS 17.1.1 compiler, got {version}'
subprocess.run(['rebar3', 'compile'], cwd=ROOT / 'control', check=True)
resources = ROOT / f'builds/intermediates/iOS/Resources-{target}/runtime'
resources.mkdir(parents=True, exist_ok=True)
for name in ['kernel', 'stdlib', 'inets', 'crypto', 'asn1', 'public_key', 'ssl']:
    matches = list((otp / 'lib').glob(f'{name}-*'))
    assert len(matches) == 1, (name, matches)
    app = matches[0]
    shutil.copytree(app / 'ebin', resources / 'lib' / app.name / 'ebin', dirs_exist_ok=True)
shutil.copytree(ROOT / 'builds/intermediates/control/default/lib/parvi/ebin',
                resources / 'lib/parvi-0.1.0/ebin', dirs_exist_ok=True)
for name in ['gun', 'cowlib']:
    shutil.copytree(ROOT / f'builds/intermediates/control/default/lib/{name}/ebin',
                    resources / f'lib/{name}/ebin', dirs_exist_ok=True)
    for license in (ROOT / f'builds/intermediates/control/default/lib/{name}').glob('LICENSE*'):
        shutil.copy2(license, resources / f'{name}-{license.name}')
# iOS does not expose the host's certificate-store loading commands to BEAM.
# Export public trust anchors at build time; never disable TLS verification.
ca_bundle = subprocess.check_output(['erl', '-noshell', '-eval',
    "Certs = [case C of {cert, DER, _} -> DER; DER when is_binary(DER) -> DER end "
    "|| C <- public_key:cacerts_get()], "
    "io:put_chars(public_key:pem_encode([{'Certificate', C, not_encrypted} || C <- Certs])), halt()."])
(resources / 'cacerts.pem').write_bytes(ca_bundle)
shutil.copy2(otp / 'releases/29/start_clean.boot', resources / 'start_clean.boot')
(resources / 'erts-17.1.1/bin').mkdir(parents=True, exist_ok=True)
shutil.copy2(ROOT / 'LICENSE', resources / 'LICENSE')
shutil.copy2(ROOT / 'Apps/iOS/MOB-LICENSE', resources / 'MOB-LICENSE')
print(f'Prepared {target}: {resources}', flush=True)
