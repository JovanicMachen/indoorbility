"""Operator-enrolled devices; secrets are hashed at rest, access JWTs last 15 minutes."""
from contextlib import contextmanager
import hashlib
import hmac
import json
import os
from pathlib import Path
import secrets
import sqlite3
import time
import jwt
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
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
        CREATE TABLE IF NOT EXISTS refresh_retry(old_hash TEXT PRIMARY KEY, request_hash TEXT NOT NULL,
            successor_hash TEXT NOT NULL, response BLOB);
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


# No fixed absolute expiry for enrolled, non-revoked devices. Device revocation
# remains authoritative, including for access tokens already issued.
DURABLE_EXPIRY = 2**62


def retry_cipher():
    secret = os.getenv('AGENT_AUTH_SECRET', '')
    if len(secret) < 32: raise HTTPException(503, 'Authentication unavailable')
    key = hmac.new(secret.encode(), b'indoorbility-refresh-retry-v1', hashlib.sha256).digest()
    return AESGCM(key)


def seal_response(value, old_hash, request_hash):
    nonce = secrets.token_bytes(12)
    aad = (old_hash + ':' + request_hash).encode()
    return nonce + retry_cipher().encrypt(nonce, json.dumps(value, separators=(',', ':')).encode(), aad)


def open_response(value, old_hash, request_hash):
    aad = (old_hash + ':' + request_hash).encode()
    try:
        return json.loads(retry_cipher().decrypt(value[:12], value[12:], aad))
    except Exception:
        # Never return secrets or revoke a device on an unreadable recovery record.
        raise HTTPException(503, 'Renewal recovery unavailable')


def credentials(db, device, expiry=DURABLE_EXPIRY):
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


class RefreshCredential(Credential):
    # A random per-rotation secret, retained on the phone until the response is saved.
    requestId: str | None = Field(default=None, min_length=32, max_length=128, pattern=r'^[A-Za-z0-9_-]+$')


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
            return credentials(db, device)

    @app.post('/auth/refresh')
    def refresh(body: RefreshCredential):
        now = int(time.time())
        old_hash = digest(body.credential)
        request_hash = digest(body.requestId) if body.requestId else None
        with connect() as db:
            db.execute('BEGIN IMMEDIATE')
            row = db.execute('SELECT r.device,r.expires,r.used,d.revoked FROM refresh r JOIN devices d ON d.id=r.device WHERE hash=?', (old_hash,)).fetchone()
            if not row or row[3]: raise HTTPException(401, 'Device authorization unavailable')
            if row[2]:
                retry = db.execute('SELECT request_hash,response FROM refresh_retry WHERE old_hash=?', (old_hash,)).fetchone()
                if retry and request_hash and hmac.compare_digest(retry[0], request_hash):
                    if retry[1] is None: raise HTTPException(409, 'Renewal already completed')
                    return open_response(retry[1], old_hash, request_hash)
                db.execute('UPDATE devices SET revoked=1 WHERE id=?', (row[0],))
                db.commit()
                raise HTTPException(401, 'Device authorization unavailable')
            # A legacy unexpired credential migrates in place, preserving device ID.
            if row[1] <= now: raise HTTPException(401, 'Device authorization unavailable')
            db.execute('UPDATE refresh SET used=1 WHERE hash=?', (old_hash,))
            # Once the successor is used, recovery of its predecessor must not
            # roll a client back to an already-consumed credential.
            db.execute('UPDATE refresh_retry SET response=NULL WHERE successor_hash=?', (old_hash,))
            result = credentials(db, row[0])
            if request_hash:
                db.execute('INSERT INTO refresh_retry(old_hash,request_hash,successor_hash,response) VALUES (?,?,?,?)',
                    (old_hash, request_hash, digest(result['refreshToken']), seal_response(result, old_hash, request_hash)))
            return result


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description='Run inside the hosted service, never on a public endpoint.')
    parser.add_argument('--revoke', metavar='DEVICE_ID')
    args = parser.parse_args()
    if args.revoke:
        revoke(args.revoke); print('Device revoked.')
    else:
        print(issue_pairing())  # operator-only code; never write it to application logs
