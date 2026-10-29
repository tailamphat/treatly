# Connecting Google Tasks

## For users

Click **Sign in** next to Google Tasks in Settings (or **Google Tasks > Sign in with Google...** in the menu). Your browser opens Google's sign-in page; log in, allow access to your tasks, and you're done. Treatly keeps the sign-in in the macOS Keychain and never sees your password.

To disconnect, use **Disconnect** in the same place. You can also remove access at [myaccount.google.com/permissions](https://myaccount.google.com/permissions).

## For maintainers: building in Google sign-in

The sign-in page needs an OAuth client that belongs to whoever ships the app. It is added at build time and never committed.

1. In [Google Cloud Console](https://console.cloud.google.com/), create a project.
2. **APIs & Services > Library**: enable **Google Tasks API**.
3. **Google Auth Platform > Branding / Audience**: set the app name (Treatly), support email and logo, choose **External**, and **Publish** the app. While it is in *Testing*, only listed test users can sign in and their sign-in expires after 7 days.
4. **Data Access**: add the scope `https://www.googleapis.com/auth/tasks`.
5. **Clients > Create client**, type **Desktop app**. Download the JSON.
6. Save it as `Config/google-oauth-client.json` (gitignored), or export `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET`.
7. `./scripts/bundle.sh`. It prints `Google sign-in: built in`.

For a Desktop app client Google does not treat the client secret as confidential; the sign-in is protected by PKCE and the loopback redirect. Still, keep it out of the repo so it isn't scraped.

The Tasks scope is a *sensitive* scope. Until Google verifies the app, users see an "unverified app" warning (Advanced > Go to Treatly) and the client is limited to 100 users. Submit the app for verification in Google Auth Platform to remove both.

## Bring your own client

Builds without a built-in client (for example `swift build` from source) ask for one when you sign in. You can also switch any build to your own client with **Google Tasks > Use Your Own OAuth Client...**: follow steps 1 to 5 above, add yourself as a test user (or publish), and paste the client ID and secret. **Use Built-in Sign-in** switches back. Your own client ID is stored in user defaults and its secret in the Keychain.

## Notes

- Sign-in uses the loopback flow (a one-shot listener on `127.0.0.1`) with PKCE.
- Google Tasks only stores a due *date*, not a time. Treatly treats it as due at the end of that day.
- Snoozing a Google task hides it locally; it can't move the due date to a specific time. Apple Reminders snoozes do move the due date.
- Google has no push updates, so Treatly polls every minute.
