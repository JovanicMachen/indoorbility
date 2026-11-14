import os
import tempfile
import time
import unittest
from unittest.mock import patch
import jwt
from fastapi.testclient import TestClient
import app
import device_auth


class DeviceAuthTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.env = patch.dict(os.environ, {'AUTH_STORAGE_PATH': self.folder.name+'/auth.sqlite', 'MAP_STORAGE_DIR': self.folder.name+'/maps', 'AGENT_AUTH_SECRET': 'x'*48, 'APP_ENV': 'production', 'RAILWAY_VOLUME_MOUNT_PATH': self.folder.name, 'OPENAI_API_KEY': 'test-only'})
        self.env.start()
        self.addCleanup(self.env.stop); self.addCleanup(self.folder.cleanup)
        app.request_rates.clear()
        self.client = TestClient(app.app)

    def pair(self):
        code = device_auth.issue_pairing()
        result = self.client.post('/auth/pair', json={'credential': code})
        self.assertEqual(result.status_code, 200)
        self.assertEqual(self.client.post('/auth/pair', json={'credential': code}).status_code, 401)
        return result.json()

    def test_pair_refresh_replay_revokes_and_owner_persists(self):
        first = self.pair()
        claims = jwt.decode(first['accessToken'], os.environ['AGENT_AUTH_SECRET'], algorithms=['HS256'], audience='indoorbility')
        self.assertEqual(claims['exp']-claims['iat'], 900)
        result = self.client.post('/auth/refresh', json={'credential': first['refreshToken']})
        self.assertEqual(result.status_code, 200)
        second = result.json()
        self.assertEqual(second['deviceId'], first['deviceId'])
        self.assertNotEqual(first['refreshToken'], second['refreshToken'])
        with device_auth.connect() as db:
            hashes = [r[0] for r in db.execute('SELECT hash FROM refresh')]
            self.assertNotIn(first['refreshToken'], hashes)
        headers = {'Authorization': 'Bearer '+second['accessToken']}
        self.assertEqual(self.client.get('/agent/check', headers=headers).status_code, 200)
        self.assertEqual(self.client.post('/auth/refresh', json={'credential': first['refreshToken']}).status_code, 401)
        self.assertEqual(self.client.get('/agent/check', headers=headers).status_code, 401)

    def test_interrupted_refresh_retries_same_request_across_backend_restart(self):
        first = self.pair()
        request = {'credential': first['refreshToken'], 'requestId': 'a' * 64}
        # The response was committed but lost in transit; a new backend instance retries.
        issued = self.client.post('/auth/refresh', json=request)
        self.assertEqual(issued.status_code, 200)
        retry = TestClient(app.app).post('/auth/refresh', json=request)
        self.assertEqual(retry.status_code, 200)
        self.assertEqual(retry.json(), issued.json())
        self.assertEqual(retry.json()['deviceId'], first['deviceId'])
        with device_auth.connect() as db:
            record = db.execute('SELECT response FROM refresh_retry').fetchone()[0]
            self.assertNotIn(issued.json()['refreshToken'].encode(), record)
        self.assertTrue(device_auth.active(first['deviceId']))
        # After the next rotation, an old retry must not roll back the phone.
        successor = self.client.post('/auth/refresh', json={'credential': issued.json()['refreshToken'], 'requestId': 'b' * 64})
        self.assertEqual(successor.status_code, 200)
        self.assertEqual(self.client.post('/auth/refresh', json=request).status_code, 409)
        self.assertTrue(device_auth.active(first['deviceId']))

    def test_different_retry_id_is_replay_and_revokes(self):
        first = self.pair()
        self.assertEqual(self.client.post('/auth/refresh', json={'credential': first['refreshToken'], 'requestId':'a'*64}).status_code, 200)
        self.assertEqual(self.client.post('/auth/refresh', json={'credential': first['refreshToken'], 'requestId':'b'*64}).status_code, 401)
        self.assertFalse(device_auth.active(first['deviceId']))

    def test_existing_unexpired_device_migrates_without_changing_id(self):
        first = self.pair()
        # Simulate an existing 30-day credential created by the deployed version.
        with device_auth.connect() as db:
            db.execute('UPDATE refresh SET expires=? WHERE hash=?', (int(time.time())+100, device_auth.digest(first['refreshToken'])))
        second = self.client.post('/auth/refresh', json={'credential':first['refreshToken'], 'requestId':'c'*64})
        self.assertEqual(second.status_code, 200)
        self.assertEqual(second.json()['deviceId'], first['deviceId'])
        with device_auth.connect() as db:
            expiry = db.execute('SELECT expires FROM refresh WHERE hash=?', (device_auth.digest(second.json()['refreshToken']),)).fetchone()[0]
        self.assertEqual(expiry, device_auth.DURABLE_EXPIRY)

    def test_renewal_remains_valid_after_thirty_days_and_backend_restart(self):
        first = self.pair()
        future = time.time() + 45 * 86400
        with patch('device_auth.time.time', return_value=future):
            second = TestClient(app.app).post('/auth/refresh', json={'credential':first['refreshToken'], 'requestId':'f'*64})
            self.assertEqual(second.status_code, 200)
            self.assertEqual(second.json()['deviceId'], first['deviceId'])
            third = TestClient(app.app).post('/auth/refresh', json={'credential':second.json()['refreshToken'], 'requestId':'g'*64})
            self.assertEqual(third.status_code, 200)
            self.assertEqual(third.json()['deviceId'], first['deviceId'])

    def test_identical_concurrent_retry_is_idempotent(self):
        from concurrent.futures import ThreadPoolExecutor
        first = self.pair()
        payload = {'credential':first['refreshToken'], 'requestId':'h'*64}
        def rotate(_):
            result = TestClient(app.app).post('/auth/refresh', json=payload)
            return result.status_code, result.json()
        with ThreadPoolExecutor(max_workers=2) as executor:
            results = list(executor.map(rotate, range(2)))
        self.assertEqual(results[0][0], 200)
        self.assertEqual(results[0], results[1])
        self.assertTrue(device_auth.active(first['deviceId']))

    def test_real_backend_restart_and_temporary_network_loss(self):
        import httpx, socket, subprocess, sys
        from pathlib import Path
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            port = sock.getsockname()[1]
        base = f'http://127.0.0.1:{port}'
        client = httpx.Client(trust_env=False, timeout=1)
        self.addCleanup(client.close)
        process = None
        def stop():
            nonlocal process
            if process and process.poll() is None:
                process.terminate()
                try: process.wait(timeout=5)
                except subprocess.TimeoutExpired: process.kill(); process.wait(timeout=5)
            process = None
        self.addCleanup(stop)
        def start():
            nonlocal process
            process = subprocess.Popen([sys.executable, '-m', 'uvicorn', 'app:app', '--host', '127.0.0.1', '--port', str(port), '--no-access-log'],
                cwd=str(Path(__file__).parent), env=os.environ.copy(), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            for _ in range(100):
                if process.poll() is not None: self.fail('Backend process exited during startup')
                try:
                    if client.get(base+'/health').status_code == 200: return
                except httpx.TransportError: pass
                time.sleep(0.05)
            self.fail('Backend did not start')
        start()
        first = client.post(base+'/auth/pair', json={'credential':device_auth.issue_pairing()}).json()
        payload = {'credential':first['refreshToken'], 'requestId':'i'*64}
        committed = client.post(base+'/auth/refresh', json=payload).json()
        stop()
        with self.assertRaises(httpx.TransportError): client.post(base+'/auth/refresh', json=payload)
        start()
        retry = client.post(base+'/auth/refresh', json=payload)
        self.assertEqual(retry.status_code, 200)
        self.assertEqual(retry.json(), committed)
        self.assertEqual(committed['deviceId'], first['deviceId'])
        self.assertEqual(client.get(base+'/agent/check', headers={'Authorization':'Bearer '+committed['accessToken']}).status_code, 200)

    def test_revocation_blocks_recovery_and_future_refresh(self):
        first = self.pair()
        request = {'credential':first['refreshToken'], 'requestId':'d'*64}
        second = self.client.post('/auth/refresh', json=request).json()
        device_auth.revoke(first['deviceId'])
        self.assertEqual(self.client.post('/auth/refresh', json=request).status_code, 401)
        self.assertEqual(self.client.post('/auth/refresh', json={'credential':second['refreshToken'], 'requestId':'e'*64}).status_code, 401)
        self.assertEqual(self.client.get('/agent/check', headers={'Authorization':'Bearer '+second['accessToken']}).status_code, 401)

    def test_restart_persistence_and_revoke(self):
        first = self.pair()
        app.runs.clear()  # ephemeral AI turns do not affect durable device identity
        client = TestClient(app.app)
        self.assertEqual(client.post('/auth/refresh', json={'credential': first['refreshToken']}).status_code, 200)
        device_auth.revoke(first['deviceId'])
        self.assertEqual(client.get('/agent/check', headers={'Authorization':'Bearer '+first['accessToken']}).status_code, 401)

    def test_expired_pairing_and_production_rejects_legacy(self):
        code = device_auth.issue_pairing()
        with device_auth.connect() as db: db.execute('UPDATE pairing SET expires=0')
        self.assertEqual(self.client.post('/auth/pair', json={'credential':code}).status_code, 401)
        now = int(time.time())
        token = jwt.encode({'sub':'test','iat':now,'exp':now+300,'aud':'indoorbility','iss':'indoorbility-dev'},os.environ['AGENT_AUTH_SECRET'],algorithm='HS256')
        self.assertEqual(self.client.get('/agent/check', headers={'Authorization':'Bearer '+token}).status_code, 401)

    def test_map_ownership_survives_renewal_and_new_client(self):
        import base64, hashlib, json
        from uuid import uuid4
        first = self.pair()
        headers = {'Authorization':'Bearer '+first['accessToken']}
        sid = str(uuid4())
        files = {'scan.json':json.dumps({'id':sid}).encode(), 'world.arworldmap':b'opaque test archive', 'mesh.json':b'[]'}
        package = {'version':1, 'name':'Synthetic persistence test', 'scans':[{'id':sid,
            'files':{k:base64.b64encode(v).decode() for k,v in files.items()},
            'hashes':{k:hashlib.sha256(v).hexdigest() for k,v in files.items()}}]}
        uploaded = self.client.post('/maps', json=package, headers=headers)
        self.assertEqual(uploaded.status_code, 200)
        url = '/maps/'+uploaded.json()['code']
        fresh = TestClient(app.app)
        second = fresh.post('/auth/refresh', json={'credential':first['refreshToken']}).json()
        headers = {'Authorization':'Bearer '+second['accessToken']}
        downloaded = fresh.get(url, headers=headers)
        self.assertEqual(downloaded.status_code, 200)
        self.assertEqual(hashlib.sha256(downloaded.content).hexdigest(), uploaded.json()['sha256'])
        self.assertEqual(fresh.delete(url, headers=headers).status_code, 200)
        self.assertEqual(fresh.get(url, headers=headers).status_code, 404)

    def test_expired_refresh_rejected(self):
        first = self.pair()
        with device_auth.connect() as db: db.execute('UPDATE refresh SET expires=0')
        self.assertEqual(self.client.post('/auth/refresh', json={'credential':first['refreshToken']}).status_code, 401)

    def test_readiness_requires_persistent_storage_and_configuration(self):
        self.assertEqual(self.client.get('/ready').status_code, 200)
        with patch.dict(os.environ, {'AUTH_STORAGE_PATH':'/tmp/outside-volume.sqlite'}):
            self.assertEqual(self.client.get('/ready').status_code, 503)
        with patch.dict(os.environ, {'OPENAI_API_KEY':''}):
            self.assertEqual(self.client.get('/ready').status_code, 503)

    def test_auth_rate_limit_and_no_input_echo(self):
        private = 'never-echo-this-credential'
        response = self.client.post('/auth/pair', json={'credential':private, 'extra':private})
        self.assertEqual(response.status_code, 422)
        self.assertNotIn(private, response.text)
        for _ in range(59): self.client.post('/auth/pair', json={'credential':private})
        self.assertEqual(self.client.post('/auth/pair', json={'credential':private}).status_code, 429)

if __name__ == '__main__': unittest.main()
