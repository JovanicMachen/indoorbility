"""Operator-enrolled devices; secrets are hashed at rest, access JWTs last 15 minutes."""
from contextlib import contextmanager
import hashlib
import os
from pathlib import Path
import secrets
import sqlite3
import time
import jwt
from fastapi import HTTPException
from pydantic import BaseModel, ConfigDict, Field


@contextmanager
def connect():
    path = Path(os.getenv('AUTH_STORAGE_PATH') or Path(__file__).with_name('device-auth.sqlite'))
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    db = sqlite3.connect(path, timeout=5)
    db.execute('PRAGMA journal_mode=WAL')
    db.executescript('''
        CREATE TABLE IF NOT EXISTS devices(id TEXT PRIMARY KEY, revoked INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE IF NOT EXISTS pairing(hash TEXT PRIMARY KEY, expires INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS refresh(hash TEXT PRIMARY KEY, device TEXT NOT NULL, expires INTEGER NOT NULL, used INTEGER NOT NULL DEFAULT 0);
    ''')
    os.chmod(path, 0o600)
    try:
        with db:
            yield db
    finally:
        db.close()


def digest(value): return hashlib.sha256(value.encode()).hexdigest()


def issue_pairing():
    code = secrets.token_urlsafe(24)
    with connect() as db:
        db.execute('DELETE FROM pairing WHERE expires < ?', (int(time.time()),))
        db.execute('INSERT INTO pairing VALUES (?, ?)', (digest(code), int(time.time())+600))
    return code


def active(device):
    with connect() as db:
        row = db.execute('SELECT revoked FROM devices WHERE id=?', (device,)).fetchone()
    return row is not None and row[0] == 0


def revoke(device):
    with connect() as db:
        db.execute('UPDATE devices SET revoked=1 WHERE id=?', (device,))


def credentials(db, device, expiry):
    now = int(time.time())
    secret = os.getenv('AGENT_AUTH_SECRET', '')
    if len(secret) < 32: raise HTTPException(503, 'Authentication unavailable')
    refresh = secrets.token_urlsafe(48)
    db.execute('INSERT INTO refresh VALUES (?, ?, ?, 0)', (digest(refresh), device, expiry))
    token = jwt.encode({'sub': device, 'device': True, 'iat': now, 'exp': now+900,
                        'iss': os.getenv('AGENT_TOKEN_ISSUER', 'indoorbility-dev'), 'aud': 'indoorbility'}, secret, algorithm='HS256')
    return {'accessToken': token, 'refreshToken': refresh, 'expiresAt': now+900, 'deviceId': device}


class Credential(BaseModel):
    model_config = ConfigDict(extra='forbid')
    credential: str = Field(min_length=20, max_length=256)


def install(app):
    @app.post('/auth/pair')
    def pair(body: Credential):
        now = int(time.time())
        with connect() as db:
            db.execute('BEGIN IMMEDIATE')
            row = db.execute('SELECT expires FROM pairing WHERE hash=?', (digest(body.credential),)).fetchone()
            if not row or row[0] <= now: raise HTTPException(401, 'Pairing code expired or invalid')
            db.execute('DELETE FROM pairing WHERE hash=?', (digest(body.credential),))
            device = secrets.token_urlsafe(24)
            db.execute('INSERT INTO devices(id) VALUES (?)', (device,))
            return credentials(db, device, now+30*86400)

    @app.post('/auth/refresh')
    def refresh(body: Credential):
        now = int(time.time())
        with connect() as db:
            db.execute('BEGIN IMMEDIATE')
            row = db.execute('SELECT r.device,r.expires,r.used,d.revoked FROM refresh r JOIN devices d ON d.id=r.device WHERE hash=?', (digest(body.credential),)).fetchone()
            if not row or row[1] <= now or row[3]: raise HTTPException(401, 'Pair this phone again')
            if row[2]:
                db.execute('UPDATE devices SET revoked=1 WHERE id=?', (row[0],))
                db.commit()  # replay revocation must survive the error response
                raise HTTPException(401, 'Pair this phone again')
            db.execute('UPDATE refresh SET used=1 WHERE hash=?', (digest(body.credential),))
            db.execute('DELETE FROM refresh WHERE expires < ?', (now,))
            return credentials(db, row[0], row[1])


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description='Run inside the hosted service, never on a public endpoint.')
    parser.add_argument('--revoke', metavar='DEVICE_ID')
    args = parser.parse_args()
    if args.revoke:
        revoke(args.revoke); print('Device revoked.')
    else:
        print(issue_pairing())  # operator-only code; never write it to application logs
