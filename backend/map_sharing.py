"""Explicit, authenticated map exchange. No camera data or automatic publishing."""
import asyncio
import base64
import hashlib
import json
import os
import re
import secrets
import threading
from pathlib import Path
from uuid import UUID
from fastapi import Header, HTTPException, Request
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

LIMIT = 80 * 1024 * 1024
ALLOWED = {'scan.json', 'hallway.json', 'world.arworldmap', 'mesh.json', 'room-metadata.json'}
_lock = threading.Lock()

def validate_package(raw):
    try:
        if len(raw) > LIMIT: raise ValueError()
        parcel = json.loads(raw)
        if parcel['version'] != 1 or not isinstance(parcel['name'], str) or not 1 <= len(parcel['name']) <= 200: raise ValueError()
        scans = parcel['scans']
        if not isinstance(scans, list) or not 1 <= len(scans) <= 32: raise ValueError()
        ids = set(); total = 0
        for record in scans:
            sid = str(UUID(record['id']))
            if sid in ids: raise ValueError()
            ids.add(sid)
            files = record['files']; hashes = record['hashes']
            if not isinstance(files, dict) or not isinstance(hashes, dict): raise ValueError()
            if not set(files) <= ALLOWED or set(files) != set(hashes) or not {'scan.json','world.arworldmap','mesh.json'} <= set(files): raise ValueError()
            for name, encoded in files.items():
                data = base64.b64decode(encoded, validate=True); total += len(data)
                if total > LIMIT or hashlib.sha256(data).hexdigest() != hashes[name]: raise ValueError()
                if name == 'scan.json':
                    draft = json.loads(data)
                    if str(UUID(draft['id'])) != sid: raise ValueError()
                    if len(draft.get('samples', [])) > 20000 or len(draft.get('landmarks', [])) > 500: raise ValueError()
        # Device validates AR archives, route geometry and field review; server never asserts safety.
        return parcel
    except (ValueError, TypeError, KeyError, OverflowError, RecursionError):
        raise HTTPException(422, 'Invalid map package or checksum') from None

def install_map_routes(app, authenticate):
    def root():
        path = Path((os.getenv('MAP_STORAGE_DIR') or str(Path(__file__).parent / 'map-storage')))
        path.mkdir(parents=True, exist_ok=True, mode=0o700)
        return path
    def owner_id(owner): return hashlib.sha256(owner.encode()).hexdigest()
    def location(code):
        if not re.fullmatch(r'[0-9a-f]{32}', code): raise HTTPException(404, 'Map not found')
        return root() / code
    @app.post('/maps')
    async def upload(request: Request, authorization: str | None = Header(default=None)):
        owner = owner_id(authenticate(authorization))
        raw = await request.body(); await asyncio.to_thread(validate_package, raw)
        # Atomic immutable copies; a code is a capability within authenticated backend users.
        # Single worker required: this lock and existing agent sessions are process-local.
        def persist():
            with _lock:
                folder = root(); metas = []
                for path in folder.glob('*.meta'):
                    try: metas.append(json.loads(path.read_text()))
                    except (ValueError, OSError): raise HTTPException(503, 'Map storage needs maintenance') from None
                if sum(p.stat().st_size for p in folder.iterdir() if p.is_file()) + len(raw) > 1024*1024*1024 or sum(m['size'] for m in metas if m['owner'] == owner) + len(raw) > 240*1024*1024:
                    raise HTTPException(507, 'Map storage quota exceeded; revoke old uploads')
                code = secrets.token_hex(16); target = folder / code
                digest = hashlib.sha256(raw).hexdigest()
                try:
                    with target.open('xb') as f: f.write(raw)
                    target.with_suffix('.meta').write_text(json.dumps({'owner': owner, 'size': len(raw), 'sha256': digest}))
                except OSError:
                    target.unlink(missing_ok=True); target.with_suffix('.meta').unlink(missing_ok=True)
                    raise HTTPException(503, 'Unable to save map') from None
            return {'code': code, 'sha256': digest}
        return await asyncio.to_thread(persist)
    @app.get('/maps/{code}')
    def download(code: str, authorization: str | None = Header(default=None)):
        authenticate(authorization); path = location(code)
        try: metadata = json.loads(path.with_suffix('.meta').read_text())
        except (OSError, ValueError): raise HTTPException(404, 'Map not found') from None
        if not path.is_file(): raise HTTPException(404, 'Map not found')
        return FileResponse(path, media_type='application/json', headers={'X-Content-SHA256': metadata['sha256'], 'Cache-Control': 'no-store', 'Content-Disposition': 'attachment; filename="building.indoormap"'})
    @app.delete('/maps/{code}')
    def revoke(code: str, authorization: str | None = Header(default=None)):
        owner = owner_id(authenticate(authorization)); path = location(code)
        with _lock:
            try: metadata = json.loads(path.with_suffix('.meta').read_text())
            except (OSError, ValueError): raise HTTPException(404, 'Map not found') from None
            if metadata['owner'] != owner: raise HTTPException(403, 'Only the uploader can revoke this copy')
            path.unlink(missing_ok=True); path.with_suffix('.meta').unlink(missing_ok=True)
        return {'status': 'revoked'}
    app.mount('/viewer', StaticFiles(directory=Path(__file__).parent / 'viewer', html=True), name='map-viewer')
