# Account enrollment plan

This is a design for a future release; it does not enable public signup or anonymous use.

- Add Sign in with Apple only after Apple Developer and App Store Connect identifiers, entitlements, and a documented enrollment policy are configured.
- Verify Apple identity tokens server-side using Apple signing keys, issuer, audience, expiry, nonce and replay checks. Never accept a client-supplied Apple user ID as proof.
- Add an account table with a unique issuer/subject mapping and a device-to-account association. Keep the existing device IDs and current map ownership unchanged; account linking must require proof of both the existing device credential and the account session.
- Keep new account/device enrollment behind an explicit allowlist or other approved admission control, with rate and spending limits. A valid Apple account alone must not grant unrestricted OpenAI usage.
- Issue the same short-lived access and rotating device credentials after authorized enrollment. Support account-level and per-device revocation, credential recovery, abuse monitoring without logging private location or commands, and ownership-preserving unlink/delete policies.
- Test Apple token verification, nonce replay, account linking, existing map ownership, denial of unauthorized accounts, and revocation before enabling enrollment.
