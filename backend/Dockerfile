FROM python:3.14-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 APP_ENV=production \
    MAP_STORAGE_DIR=/data/maps AUTH_STORAGE_PATH=/data/device-auth.sqlite AGENT_TOKEN_ISSUER=indoorbility
WORKDIR /app
COPY requirements.lock.txt ./
RUN pip install --no-cache-dir -r requirements.lock.txt
COPY app.py map_sharing.py device_auth.py general_assistant.py ./
COPY viewer ./viewer
CMD ["sh", "-c", "umask 077; exec uvicorn app:app --host 0.0.0.0 --port ${PORT:-8080} --workers 1 --no-access-log --limit-concurrency 32 --timeout-keep-alive 5"]
