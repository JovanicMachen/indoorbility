# Railway deployment and iPhone verification

Status: deployed and verified on November 14, 2026 at https://indoorbility-production.up.railway.app. The app now defaults to this URL and migrates existing temporary `trycloudflare.com` settings once. A phone must pair with this backend; old development tokens are not accepted. Physical iPhone/cellular/ARKit verification remains outstanding.

## Local validation — November 14, 2026

- Backend: 24 tests passed, including credential rotation/revocation, mounted-storage readiness and map ownership across renewal.
- Swift core: 123 tests passed.
- Generic iPhone build: passed with code signing disabled; this is not an installed-device test.
- Simulator UI suite: 10 passed, 10 failed. Failures include expectations for removed Help/Map buttons, changed room/setup labels, the updated “Continue straight” instruction, and an unreachable `lastNarration` element. These remain unresolved; the UI suite is not green.
- Hosted HTTPS: `/health` and `/ready` returned 200; unauthenticated `/agent/check` returned 401.
- One-use pairing, authenticated map upload/download and SHA-256 checks passed against the actual service.
- Real OpenAI → existing Swift probe: Room 106 → Room 105 changed successfully with synthetic pose preserved. Scene-unavailable handling passed. This is not physical ARKit verification.
- After a real service restart, device renewal and saved-map checksum passed. The synthetic upload was deleted and the test device revoked.
- Physical cellular/ARKit tests remain pending.

Requested Railway project: `8d7bf107-d641-4305-8acb-38c657b7428e`.

Service: `e3fab07e-bb67-4ab5-9777-6df86dcf65ce`; production environment: `4c9694e6-5e3b-44f6-b28c-9b64d1f79419`. Verified deployment: `79ec8a91-0e17-4875-bb8e-52751c1729ba`. The existing failed GitHub source was disconnected; deploy the prepared backend explicitly until CI is configured. No application source or secrets were pushed to GitHub.

The attached volume is 500 MB. Scheduled backups were requested through Railway's infrastructure tooling but did not appear in the subsequent plan, so they are **not verified as enabled**; configure and verify them in the volume dashboard. The trial account must retain sufficient hosting credit or an active plan for continued availability.

## Architecture retained

The existing FastAPI/OpenAI Agents SDK coordinator stays in `backend`. Swift executes and validates tools, routes, revisions and pose evidence on the iPhone. ARKit, LiDAR, speech, downloaded maps and deterministic navigation never move to the server. A network failure does not restart ARKit or undo a completed tool action.

One Railway service, one worker, one replica, persistent volume at `/data`, service sleeping disabled. No Supabase, database service or routing replacement is required. SQLite uses the standard library for a small device credential registry. Uploaded map files stay in `/data/maps`.

## Account and secrets

1. Sign in with Railway CLI (`railway login`) and link an authorized project/service. A paid plan or trial with sufficient resources is required; check Railway's account billing before provisioning.
2. Create the backend service and attach a persistent volume at `/data` **before** deploying. Enable volume backups in Railway. Do not scale this service to multiple replicas/workers: current AI runs, rate limits and upload locks are process-local.
3. Set Railway service variables:

   | Variable | Value |
   | --- | --- |
   | `APP_ENV` | `production` |
   | `OPENAI_API_KEY` | Existing authorized OpenAI project key; secret |
   | `OPENAI_MODEL` | Existing configured model |
   | `AGENT_AUTH_SECRET` | New random server-only value of at least 32 characters |
   | `AGENT_TOKEN_ISSUER` | `indoorbility` |
   | `MAP_STORAGE_DIR` | `/data/maps` |
   | `AUTH_STORAGE_PATH` | `/data/device-auth.sqlite` |

   Railway supplies `PORT` and `RAILWAY_VOLUME_MOUNT_PATH`. Do not fake the volume variable to pass readiness. Seal the two secret variables in Railway. Do not print variable lists, paste secrets into chat, pass values on shell command lines, or include `.env` in uploads. CLI supports `railway variable set NAME --stdin --skip-deploys`; feed secrets through stdin from a trusted local process and suppress secret-bearing command output.
4. Deploy **only the backend directory**, using `railway up backend --path-as-root` from the project root (or run from an explicitly staged backend folder). The Dockerfile uses explicit source copies. `.dockerignore` and `.railwayignore` exclude `.env`, virtual environments, maps, credentials and test artifacts. Do not upload the whole Mac project. Deployment settings are recorded in `backend/.railway/railway.ts`, because Railway reports that legacy `railway.json` support ends December 1, 2026. To apply infrastructure changes, use Railway's CLI and its `railway` TypeScript SDK in a separate deployment workspace; review `railway config plan` before `railway config apply`. This tooling is not an iOS or Python runtime dependency. Variables remain unmanaged by infrastructure files, so secrets never enter source configuration.
5. Generate a Railway public HTTPS domain. Keep this domain stable. Healthcheck is `/ready`; `/health` is liveness. Readiness verifies credentials are configured and both data paths are under the mounted, writable volume. It does not prove OpenAI API billing/model access; the real-agent probe does that.

## Pair a phone without keeping the Mac on

In a Railway **remote service shell** run `python device_auth.py`. This prints a high-entropy, one-use pairing code valid for ten minutes. This is an operator command, not a public issuance API. Keep it out of shared logs. In iPhone Settings → AI connection, enter the hosted HTTPS URL and pairing code, then tap **Pair this iPhone** and **Check backend connection**.

The phone receives a 15-minute access token and rotating renewal credential in device-only Keychain storage, scoped to that backend URL. Renewal lasts up to 30 days from pairing, then requires pairing again. No OpenAI key or signing secret is sent to the phone. Replaying an already-used renewal credential revokes that device; a lost renewal response can therefore require re-pairing. Revoke an enrolled phone remotely with `python device_auth.py --revoke DEVICE_ID`. Server-secret rotation invalidates access tokens; use device revocation too when renewal credentials must be invalidated.

Operator enrollment is suitable for the existing private/test app. It is not public account signup or Apple App Attest. A public release needs an enrollment/identity policy. Legacy operator-issued JWTs are rejected in production.

## Persistence audit

- Uploaded maps: durable volume, existing checksum verification and uploader-only deletion retained; blocking upload writes moved off the ASGI event loop.
- Device identity, hashed pairing/refresh credentials and revocation: SQLite on the same durable volume. Identity remains stable across renewal, preserving ownership of uploads.
- Active AI turns: intentionally in memory, at most 180 seconds and four device calls. They expire on restart rather than replaying stale navigation actions. Phone falls back locally; issue a new command after reconnection.
- Saved scans, review status, preferences, routes and shopping tasks: remain on the iPhone. No automatic cloud upload or transcript persistence.
- No local backend map-storage directory existed at preparation time. Any later local uploads must be explicitly exported/re-uploaded or migrated with their ownership metadata; never place them in the Docker image. Re-pairing creates a new device identity, so old upload ownership does not automatically transfer.
- Runtime logs exclude request bodies, authorization headers, audio, camera frames and pose history. Access logs and Agents SDK tracing are disabled. Auth validation responses do not echo submitted credentials. Provider failures report only error category/status.
- Boundaries: 20 agent requests/minute/device, 20 map requests/minute/device, 60 pairing/renewal requests/minute/service; bounded request sizes and model/client timeouts. This is basic single-instance protection, not a distributed anti-abuse system.

## Verify the actual deployment before changing the production URL

1. Build the Swift probe (`swift build --product IndoorbilityAgentProbe`). In a hosted remote shell issue a pairing code.
2. Run locally, entering that code at the hidden prompt:

   ```sh
   backend/.venv/bin/python backend/verify_deployment.py \
     --base https://YOUR-STABLE-DOMAIN \
     --state /tmp/indoorbility.deployment-state.json --agent
   ```

   This tests public HTTPS readiness, unauthorized rejection, one-use pairing, authenticated calls, map upload/download checksums, and real OpenAI calls into actual Swift tool execution. The Swift probe uses a **synthetic pose**, not an iPhone or ARKit. Never describe this as a physical-device accuracy test.
3. Restart/redeploy the Railway service, keeping its volume, then run the same command with `--after-restart`. It renews the credential, verifies the saved map checksum, revokes the uploaded synthetic fixture and deletes the private local state. The state file contains a renewal credential; never commit it. Revoke the test device afterward in the hosted shell.
4. These hosted checks passed and `AgentConfiguration.productionBaseURL` now uses the verified stable HTTPS URL. Temporary Cloudflare overrides migrate automatically once; custom backend overrides are preserved. Pair with Railway, rebuild/install and check connection. Future endpoint changes must pass these checks again before switching users.
5. A volume is durable but not a backup. Enable scheduled backups and test restoration. A restart can briefly interrupt cloud AI; local directions must keep working.

## Physical iPhone test — cellular, Mac powered off

1. Install the updated signed app; download and independently review a measured Friend Center route. Pair with the verified Railway service and allow cellular data for Indoorbility. Switch off Wi-Fi, then power off the Mac.
2. Confirm a known starting landmark and start indoor navigation. Export diagnostics noting session reset count and map-position confidence.
3. Say “Take me to [another actually mapped room].” Verify Agent timeline shows resolve → calculate → change, the real destination changes, and the ARSession reset count does not increase. Do not use invented room geometry.
4. Keep the app open for more than 15 minutes; repeat an AI command to verify automatic credential renewal over cellular. Reopen the app and repeat.
5. Upload a test map, download it on another authorized phone, verify its checksum and local review requirement, then revoke the upload. Restart the Railway service and verify saved uploads still exist.
6. Disable cellular and Wi-Fi. Existing local directions, speech, downloaded maps and stop/repeat controls must work. An AI request should show **Cloud AI unavailable. Local navigation continues.** Re-enable cellular and submit a new request; no camera restart should be needed.
7. Cover the camera while stationary to verify indoor position uncertainty still pauses unsafe directions. Network independence must not bypass tracking safeguards. Confirm arrival only at the measured, correct room.

Record actual outcomes, latency, diagnostics and failures. The deployed backend cannot establish physical accuracy by itself.

References: [Railway volumes](https://docs.railway.com/volumes), [sealed variables](https://docs.railway.com/variables), [healthchecks](https://docs.railway.com/deployments/healthchecks), [CLI deployment](https://docs.railway.com/cli/up).
