# Test the real Indoorbility agent on your iPhone

Verified November 14, 2026: real OpenAI tool calls changed actual Swift routing state to Room 106, then Room 105 with the synthetic starting coordinate preserved. See REAL_AGENT_VERIFICATION.json for actual run/call IDs. Camera invocation returned unavailable in the command-line harness, as expected. This does not verify physical ARKit, speech or camera behavior.

## Running now

The development backend is running on http://127.0.0.1:8765. Port 8000 was already occupied and was left alone.

Temporary iPhone HTTPS base URL:

https://benchmark-sustainable-sends-nearly.trycloudflare.com

Public /health returned 200. Local authenticated /agent/check returned 200; requests without a token returned 401. Automatic approval review blocked sending a token through the tunnel, so authenticated remote transport has not been verified. The URL works only while this Mac, backend and tunnel remain running. Keep the Mac awake. Restarting the tunnel changes its URL.

## Restart commands (only if the current processes stop)

Terminal 1:

```sh
cd "/Users/jovanic/Desktop/Hackprinceton Project/indoorblity"
python3 -m venv backend/.venv
backend/.venv/bin/pip install -r backend/requirements.lock.txt
backend/.venv/bin/uvicorn backend.app:app --host 127.0.0.1 --port 8765 --no-access-log
```

The backend automatically reads backend/.env. OPENAI_API_KEY, OPENAI_MODEL and AGENT_AUTH_SECRET are already configured there. Do not put either server secret in Xcode or the app. Existing process environment variables take precedence; restart the server after changing .env.

Terminal 2:

```sh
/opt/homebrew/bin/cloudflared tunnel --url http://127.0.0.1:8765 --no-autoupdate
```

Copy the new HTTPS URL printed by cloudflared if you restart it.

## Connect the app

1. Connect and unlock the iPhone. Open Indoorbility.xcodeproj in Xcode, select the physical phone and run with your signing team. The current build succeeded without signing; installation requires your usual signing setup.
2. Generate a one-hour app access token on your Mac:

```sh
cd "/Users/jovanic/Desktop/Hackprinceton Project/indoorblity"
backend/.venv/bin/python backend/issue_token.py | pbcopy
```

3. In Indoorbility, open Settings → AI connection. Enter the HTTPS base URL above, without /agent/turn. Paste the app token (Universal Clipboard if enabled), then tap Save access token. This is an expiring app credential, never the OpenAI key or server signing secret.
4. Enable Use cloud navigation assistant, then Check backend connection. Expect “Connected and authenticated.” This verifies transport/authentication, not an inference by itself. Regenerate the app token when it expires.
5. Enable Show agent timeline. During navigation, open More → Agent timeline to inspect actual calls and execution results.

## Physical navigation demonstration

Use a reviewed hallway scan containing a confirmed entrance, Room 105 and Room 106 on the same connected mapped path. The cloud agent cannot discover unmapped rooms or invent alternate corridors. Open the mapped hallway navigation and relocalize/confirm the entrance before issuing commands. A sighted spotter should accompany prototype testing.

1. With verified tracking active, tap the microphone and say “Take me to Room 106.” Check resolveDestination → calculateAccessibleRoute → changeDestination in the timeline, and verify the displayed destination.
2. While navigating, say “Actually, Room 105 instead.” Verify the displayed route changes from the current live pose, camera tracking continues, obsolete speech stops and the updated instruction is spoken. Inspect session/pose preservation diagnostics; successful fixture tests do not prove this hardware behavior.
3. Say “What’s in front of me?” Allow camera permission. The current tool reports locally recognized text and available central measured depth, with uncertainty. Object identities remain unknown; this is not general visual scene recognition or guaranteed obstacle avoidance. No camera image is uploaded to OpenAI.
4. Interrupt tracking: guidance should pause and offer landmark recovery rather than guess a position. Restore verified tracking before continuing.
5. Disable cloud access or stop the server: existing deterministic navigation/local assistant should remain usable.

If an unknown room is requested, an error is correct. If a verified closure blocks this single hallway, “no verified alternative” is correct; a detour requires another surveyed connection.

## Repeat the real model test from the Mac

```sh
cd "/Users/jovanic/Desktop/Hackprinceton Project/indoorblity"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --product IndoorbilityAgentProbe
backend/.venv/bin/python backend/evaluate_live.py
```

This incurs actual OpenAI calls and executes actual Swift route tools using synthetic coordinates. It does not pretend to have a camera. The probe mints its short-lived localhost token internally; it prints no credentials.
