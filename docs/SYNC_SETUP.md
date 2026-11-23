# Sync between devices (Google Drive) — one-time setup

Quiz me keeps phone and PC in sync through a **private app folder in your Google Drive**
(`drive.appdata` scope: the app sees only its own folder, never your other files).
The code is in `lib/sync/`. Builds need three Google OAuth client ids, and the Android
build needs a permanent signing key. None of these are stored in the repository: they are
GitHub repository secrets that CI passes to the build.

## 1. Repository secrets

GitHub → repository → **Settings → Secrets and variables → Actions → New repository secret**

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | base64 of the release keystore (`.jks`) |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password |
| `ANDROID_KEY_ALIAS` | key alias |
| `ANDROID_KEY_PASSWORD` | key password |
| `QUIZME_GOOGLE_WEB_CLIENT_ID` | OAuth client id of type *Web application* (used by Android sign-in) |
| `QUIZME_GOOGLE_DESKTOP_CLIENT_ID` | OAuth client id of type *Desktop app* (Windows) |
| `QUIZME_GOOGLE_DESKTOP_CLIENT_SECRET` | client secret of the *Desktop app* client |

Without the Google secrets the app shows "Google sign-in is not set up in this version".
Without the signing secrets CI signs with a throw-away debug key, and Google sign-in on
Android will not work (the Android OAuth client is tied to the key's SHA-1).

## 2. Google Cloud project

1. Open <https://console.cloud.google.com/> and create a project, e.g. **Quiz me**.
2. **APIs & Services → Library →** search **Google Drive API → Enable**.
3. **Google Auth Platform** (OAuth consent screen):
   - *Branding*: app name **Quiz me**, your email as support and developer contact.
   - *Audience*: **External**, then **Publish app** (status *In production*). Only
     non-sensitive scopes are used, so Google does not require verification, and published
     apps keep their sign-in (apps left in *Testing* are signed out after 7 days).
   - *Data access*: **Add or remove scopes** → `.../auth/drive.appdata` → Save.
4. **Clients → Create client**, three times:
   - **Android** — package name `com.radyradwan.quiz_me`, SHA-1 of the release key.
   - **Web application** — name "Quiz me (Android sign-in)", no URIs needed → copy the
     *Client ID* into `QUIZME_GOOGLE_WEB_CLIENT_ID`.
   - **Desktop app** — name "Quiz me (Windows)" → copy *Client ID* and *Client secret* into
     `QUIZME_GOOGLE_DESKTOP_CLIENT_ID` / `QUIZME_GOOGLE_DESKTOP_CLIENT_SECRET`.

Then run CI again (push, or *Actions → CI → Run workflow*).

## 3. Switching the phone to the permanently signed app

An APK signed with a different key cannot update the installed app. Once:

1. Old app: **Settings → Backup & restore → Create backup**, save the file.
2. Uninstall Quiz me, install the new APK, **restore** the backup.
3. **Settings → Sync between devices → Sign in with Google and turn on sync.**
4. On the PC: install the new Windows build, turn on sync, and choose
   **Use Google Drive data** if asked.

## How sync works

- Every change to banks, questions, progress, schedules, quiz history, bookmarks, notes,
  goals and achievements is recorded per row (`sync_meta`, maintained by SQLite triggers,
  deletions included).
- A sync downloads the shared copy, applies rows that changed later elsewhere (latest change
  wins; ties are broken by content so every device decides the same), uploads the result if
  it differs, and copies question images/audio that a device lacks.
- Runs when the app starts or returns to the foreground, ~15 s after a change, every 3
  minutes while open, and from **Sync now**.
- Settings (theme, fonts, reminders…) stay per device.
- First connection with data on both sides: *Combine*, *Use Google Drive data* or
  *Use this device's data* (the latter makes the other devices switch to it on their next sync).
- Windows stores the Google refresh token encrypted with Windows DPAPI; Android uses the
  system Google account.
