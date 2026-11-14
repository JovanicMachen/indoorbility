# Repository setup and backend hosting

The repository preserves the original remote README heading and history. Application source is unchanged by the GitHub preparation.

## Included and excluded

SwiftUI app, Xcode project, Swift package, tests, fictional demo maps, FastAPI backend, pinned dependencies, viewer, scripts and text documentation are included. Local credentials, environment files, virtual environments, Xcode user state, build outputs, captured meshes/world maps, authentication databases, personal histories, screenshots and packaged ZIP exports remain local and are ignored. The handoff ZIP's unpacked documentation and fictional fixture remain included.

The checked-in environment example has no real values for secrets. Do not commit populated copies. A Git ignore rule alone does not remove an already tracked secret; audit the proposed commit and its history before future pushes.

## Fresh checkout

1. Run `make project` to regenerate Xcode resources without the absent local Google configuration.
2. Open `Indoorbility.xcodeproj`, choose your signing team and supported iPhone. iOS 17 or later; LiDAR scanning needs compatible physical hardware.
3. Optional Google Places configuration: copy `Configuration/MapsConfig.example.plist` to ignored `LocalConfig/MapsConfig.plist`, supply your own appropriately restricted key, and run `make project` again. Never share that populated file.
4. Backend development: create a virtual environment, install `backend/requirements.lock.txt`, and copy `backend/.env.example` to ignored `backend/.env`. Set credentials privately.

## Railway preparation (no deployment performed by this GitHub upload)

The project already contains a hosted Railway URL and earlier deployment notes. This upload does not change that URL, deploy a service, or configure GitHub auto-deployment.

- Repository root directory for the backend service: `/backend`.
- Builder: existing `backend/Dockerfile` (Dockerfile path relative to service root: `Dockerfile`).
- Runtime: Python 3.14, as pinned in the Dockerfile.
- Dependencies: `pip install -r requirements.lock.txt` from `backend`. There is intentionally no separate unpinned requirements.txt.
- Start command (already in Dockerfile):

  ```sh
  umask 077; exec uvicorn app:app --host 0.0.0.0 --port ${PORT:-8080} --workers 1 --no-access-log --limit-concurrency 32 --timeout-keep-alive 5
  ```

- One replica and one worker. Attach a persistent volume at `/data` for uploaded maps and device authentication. Active agent turns are in memory.
- Health check: `/ready`; liveness: `/health`.

Configure these through Railway environment variables, never source files:

| Variable | Value |
| --- | --- |
| `APP_ENV` | `production` |
| `OPENAI_API_KEY` | Private authorized OpenAI key |
| `OPENAI_MODEL` | `gpt-4.1-mini` or the existing authorized model |
| `AGENT_AUTH_SECRET` | Private random server secret, at least 32 characters |
| `AGENT_TOKEN_ISSUER` | `indoorbility` |
| `MAP_STORAGE_DIR` | `/data/maps` |
| `AUTH_STORAGE_PATH` | `/data/device-auth.sqlite` |

Railway supplies `PORT` and the mounted-volume variable `RAILWAY_VOLUME_MOUNT_PATH`. Phones use short-lived paired credentials, not server secrets. Follow [deployment verification](RAILWAY_DEPLOYMENT.md) before any future endpoint change. Connecting this repository to a Railway service can enable deployments; do that only when deployment is authorized.
