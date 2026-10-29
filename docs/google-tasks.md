# Connecting Google Tasks

Treatly is open source, so it doesn't ship Google credentials. You create a free OAuth client once and paste it in.

1. Go to [Google Cloud Console](https://console.cloud.google.com/) and create a project (or pick one).
2. **APIs & Services > Library**: enable **Google Tasks API**.
3. **APIs & Services > OAuth consent screen**: choose *External*, fill in the app name, and add your own Google account under **Test users**.
4. **APIs & Services > Credentials > Create credentials > OAuth client ID**, application type **Desktop app**.
5. Copy the client ID and client secret.
6. In Treatly's menu bar menu: **Google Tasks > Connect Google Tasks...**, paste both, and sign in in the browser tab that opens.

The client ID is stored in user defaults; the client secret and refresh token are stored in the macOS Keychain.

## Notes

- Sign-in uses the loopback flow (a one-shot listener on `127.0.0.1`) with PKCE.
- While the consent screen is in *Testing* mode, Google expires refresh tokens after 7 days, so you'll need to reconnect weekly. Publishing the consent screen (no verification is needed for personal use with your own account) removes that limit.
- Google Tasks only stores a due *date*, not a time. Treatly treats it as due at the end of that day.
- Snoozing a Google task hides it locally; it can't move the due date to a specific time. Apple Reminders snoozes do move the due date.
- Google has no push updates, so Treatly polls every minute.
