"""Operator-only dev provisioning. Never expose an unauthenticated token-issuance endpoint."""
import os, time, secrets, jwt
from pathlib import Path
from dotenv import load_dotenv
load_dotenv(Path(__file__).with_name(".env"), override=False)
secret = os.environ.get('AGENT_AUTH_SECRET', '')
if len(secret) < 32: raise SystemExit('Set AGENT_AUTH_SECRET to at least 32 random characters first.')
now = int(time.time())
print(jwt.encode({'sub': secrets.token_urlsafe(16), 'iat': now, 'exp': now+3600, 'iss': 'indoorbility-dev', 'aud': 'indoorbility'}, secret, algorithm='HS256'))
