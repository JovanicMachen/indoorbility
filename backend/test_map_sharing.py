import base64, hashlib, json, os, tempfile, unittest, time
from unittest.mock import patch
from uuid import uuid4
import jwt
from fastapi.testclient import TestClient
import app

class MapSharingTests(unittest.TestCase):
    def setUp(self):
        self.folder=tempfile.TemporaryDirectory()
        self.env=patch.dict(os.environ, {'MAP_STORAGE_DIR': self.folder.name, 'AGENT_AUTH_SECRET':'test-secret-for-maps-only-'*3})
        self.env.start(); self.client=TestClient(app.app)
    def tearDown(self): self.env.stop(); self.folder.cleanup()
    def headers(self, owner='mapper'):
        token=jwt.encode({'sub':owner,'iat':int(time.time()),'exp':int(time.time())+600,'aud':'indoorbility','iss':'indoorbility-dev'},os.environ['AGENT_AUTH_SECRET'],algorithm='HS256')
        return {'Authorization':'Bearer '+token}
    def package(self):
        sid=str(uuid4()); files={'scan.json':json.dumps({'id':sid,'samples':[],'landmarks':[]}).encode(),'world.arworldmap':b'server-opaque-test-archive-not-device-valid','mesh.json':b'[]'}
        return {'version':1,'name':'Test map','scans':[{'id':sid,'files':{k:base64.b64encode(v).decode() for k,v in files.items()},'hashes':{k:hashlib.sha256(v).hexdigest() for k,v in files.items()}}]}
    def test_roundtrip_revoke_and_auth(self):
        parcel=self.package(); h=self.headers()
        self.assertEqual(self.client.post('/maps',json=parcel).status_code,401)
        response=self.client.post('/maps',json=parcel,headers=h);self.assertEqual(response.status_code,200)
        code=response.json()['code'];url='/maps/'+code
        self.assertEqual(self.client.get(url).status_code,401)
        downloaded=self.client.get(url,headers=self.headers('other'))
        self.assertEqual(downloaded.json(),parcel)
        self.assertEqual(hashlib.sha256(downloaded.content).hexdigest(),downloaded.headers['X-Content-SHA256'])
        self.assertEqual(self.client.delete(url,headers=self.headers('other')).status_code,403)
        self.assertEqual(self.client.delete(url,headers=h).status_code,200)
        self.assertEqual(self.client.get(url,headers=h).status_code,404)
    def test_corrupt_or_path_injected_rejected(self):
        p=self.package();p['scans'][0]['hashes']['mesh.json']='0'*64
        self.assertEqual(self.client.post('/maps',json=p,headers=self.headers()).status_code,422)
        p=self.package();p['scans'][0]['files']['../oops']=''
        self.assertEqual(self.client.post('/maps',json=p,headers=self.headers()).status_code,422)
    def test_viewer_and_agent_limit(self):
        self.assertEqual(self.client.get('/viewer/').status_code,200)
        self.assertEqual(self.client.post('/agent/turn',content=b'x'*40000).status_code,413)
    def test_map_upload_larger_than_agent_body(self):
        p=self.package();p['scans'][0]['files']['world.arworldmap']=base64.b64encode(b'x'*40000).decode()
        p['scans'][0]['hashes']['world.arworldmap']=hashlib.sha256(b'x'*40000).hexdigest()
        self.assertEqual(self.client.post('/maps',json=p,headers=self.headers()).status_code,200)

if __name__=='__main__':unittest.main()
