# Google Sign-In setup

Google Sign-In uses the OAuth 2.0 authorization-code flow with PKCE. The app refuses to start the flow until both iOS values are present, and the Worker verifies the returned ID token against the same client ID.

## Google Cloud

1. Open Google Cloud Console → APIs & Services → OAuth consent screen and finish the consent configuration.
2. Create an **OAuth client ID** with application type **iOS**.
3. Set bundle ID to `app.regulift`.
4. Copy the client ID, for example `123456.apps.googleusercontent.com`.
5. Use its reversed form as the callback scheme, for example `com.googleusercontent.apps.123456`.

## Local iOS build

Add these values to ignored `App/Secrets.local.xcconfig` without quotes:

```xcconfig
GOOGLE_CLIENT_ID = 123456.apps.googleusercontent.com
GOOGLE_REVERSED_CLIENT_ID = com.googleusercontent.apps.123456
```

`Info.plist` registers the reversed value as a URL scheme. Rebuild after changing either value.

## Worker

The Worker must verify the same audience:

```sh
cd server
npx wrangler secret put GOOGLE_CLIENT_ID
```

Paste the non-reversed iOS client ID. Deploy only through the migration-gated command:

```sh
pnpm run deploy
```

## Verification

1. Open Account → Continue with Google.
2. Complete account selection and consent.
3. Confirm Account closes and Settings shows the signed-in email.
4. Relaunch and verify the session remains signed in.
5. Sign out, sign in again, and verify the same server user is reused.
