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
