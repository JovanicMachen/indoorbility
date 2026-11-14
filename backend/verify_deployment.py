"""Hosted smoke test. State contains a refresh credential: keep outside source control."""
import argparse
import base64
import getpass
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from uuid import uuid4
from urllib.parse import urlparse
import httpx

parser = argparse.ArgumentParser()
parser.add_argument('--base', required=True)
parser.add_argument('--state', required=True, type=Path, help='Private file outside the repository, for the restart test')
parser.add_argument('--after-restart', action='store_true')
parser.add_argument('--agent', action='store_true', help='Real OpenAI + Swift probe; synthetic pose, not ARKit')
args = parser.parse_args()
base = args.base.rstrip('/')
url = urlparse(base)
if url.scheme != 'https' or not url.hostname or url.username or url.password or url.query or url.fragment:
    raise SystemExit('Use the hosted HTTPS base URL.')

def checked(response, expected=200):
    if response.status_code != expected:
        raise RuntimeError('Verification failed: HTTP '+str(response.status_code))
    return response

with httpx.Client(timeout=30, follow_redirects=False, trust_env=False) as client:
    checked(client.get(base+'/ready'))
    checked(client.get(base+'/agent/check'), 401)
    if args.after_restart:
        state = json.loads(args.state.read_text())
        if state['base'] != base: raise SystemExit('State belongs to a different backend.')
        credentials = checked(client.post(base+'/auth/refresh', json={'credential':state['refreshToken']})).json()
        state['refreshToken'] = credentials['refreshToken']
    else:
        code = getpass.getpass('One-time Railway pairing code (hidden): ')
        credentials = checked(client.post(base+'/auth/pair', json={'credential':code})).json()
        checked(client.post(base+'/auth/pair', json={'credential':code}), 401)
        state = {'base':base, 'refreshToken':credentials['refreshToken'], 'deviceId':credentials['deviceId']}
    headers = {'Authorization':'Bearer '+credentials['accessToken']}
    checked(client.get(base+'/agent/check', headers=headers))
    if not args.after_restart:
        sid = str(uuid4())
        files = {'scan.json':json.dumps({'id':sid,'samples':[],'landmarks':[]}).encode(),
                 'world.arworldmap':b'HOSTED TRANSFER TEST: NOT AN AR WORLD MAP', 'mesh.json':b'[]'}
        package = {'version':1, 'name':'Synthetic transfer test — not navigable', 'scans':[{
            'id':sid, 'files':{k:base64.b64encode(v).decode() for k,v in files.items()},
            'hashes':{k:hashlib.sha256(v).hexdigest() for k,v in files.items()}}]}
        uploaded = checked(client.post(base+'/maps', json=package, headers=headers)).json()
        state.update(uploaded)
    # Save rotated credential before doing anything else, including the model probe.
    fd = os.open(args.state, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.fchmod(fd, 0o600)
    with os.fdopen(fd, 'w') as output: json.dump(state, output)
    downloaded = checked(client.get(base+'/maps/'+state['code'], headers=headers))
    if hashlib.sha256(downloaded.content).hexdigest() != state['sha256'] or downloaded.headers.get('X-Content-SHA256') != state['sha256']:
        raise RuntimeError('Map integrity verification failed')
    if args.agent:
        env = dict(os.environ, AGENT_TEST_URL=base, AGENT_TEST_TOKEN=credentials['accessToken'])
        result = subprocess.run([sys.executable, str(Path(__file__).with_name('evaluate_live.py'))], env=env, capture_output=True, text=True)
        if result.returncode: raise RuntimeError('Real-agent probe failed; no physical-device verification implied.')
        report = json.loads(result.stdout)
        print(json.dumps({'realModel':report['modelInvocation'], 'pose':report['pose'], 'ARKitTested':report['ARKitTested'], 'outcomes':report['outcomes']}, indent=2))
    if args.after_restart:
        checked(client.delete(base+'/maps/'+state['code'], headers=headers))
        checked(client.get(base+'/maps/'+state['code'], headers=headers), 404)
        args.state.unlink()
        print('PASS: device renewal and map survived restart; checksum and revocation verified.')
        print('Revoke the test device in the hosted shell: python device_auth.py --revoke '+state['deviceId'])
    else:
        print('PASS: HTTPS readiness, authentication, one-time pairing, map upload/download checksum.')
        print('Restart the hosted service, then rerun with --after-restart to verify persistence.')
