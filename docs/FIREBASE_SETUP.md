# Accounts & sync (Firebase) — one-time setup

Quiz me accounts use **Firebase Authentication** (email + password) and store each user's
data in **Cloud Firestore**, private to that user (`firebase/firestore.rules`). The app talks
to Firebase through its REST APIs (`lib/sync/`), so the same code runs on Android and
Windows. The free **Spark** plan is enough; no credit card is needed.

Nothing secret is stored in the repository: the project id and web API key are GitHub
repository secrets that CI passes to the build with `--dart-define`.

## 1. Create the Firebase project

1. Open <https://console.firebase.google.com/> → **Create a project** → name it
   **Quiz me** (Google Analytics is not needed).
2. **Build → Authentication → Get started → Sign-in method → Email/Password → Enable → Save.**
3. **Build → Firestore Database → Create database** → choose a location near you
   (e.g. `nam5 (United States)`) → **Start in production mode** → Create.
4. Firestore → **Rules** tab → replace everything with the contents of
   `firebase/firestore.rules` → **Publish**.
5. **Project settings** (gear icon) → **General**:
   - copy the **Project ID**;
   - under *Your apps* click the **Web** icon (`</>`), register an app called "Quiz me"
     (no Hosting), then copy the **apiKey** value from the config that is shown.

## 2. Repository secrets

GitHub → repository → **Settings → Secrets and variables → Actions → New repository secret**

| Secret | Value |
|---|---|
| `QUIZME_FIREBASE_PROJECT_ID` | the Project ID |
| `QUIZME_FIREBASE_API_KEY` | the web apiKey |
| `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | optional permanent signing key, so new APKs install over old ones |

Then run CI again (push, or *Actions → CI → Run workflow*). Builds without the Firebase
secrets still work fully offline and show "Accounts are not set up in this version".

## Using it

**Settings → Account & sync** → *Create account* (first time) or *Sign in*.
Sign in with the same account on each device. Friends create their own accounts; nobody can
see anyone else's data.

## How sync works

- Every change to banks, questions, progress, schedules, quiz history, bookmarks, notes,
  goals and achievements is recorded per row (`sync_meta`, maintained by SQLite triggers,
  deletions included).
- A sync reads the account's small manifest document. If another device uploaded a new
  version it downloads it and merges it (latest change per row wins; ties are broken by
  content so every device decides the same), then uploads a new version if this device has
  changes. Uploads use a Firestore precondition, so two devices can never silently overwrite
  each other; the loser merges and retries.
- The data is a gzip-compressed snapshot split into parts of ≤ 900 KB
  (`users/{uid}/chunks`), with question images/audio up to 15 MB each in
  `users/{uid}/media` / `mediaChunks`.
- Sync runs when the app starts or returns to the foreground, ~15 s after a change, every
  3 minutes while open, and from **Sync now**. When nothing changed it costs one document read.
- Settings (theme, fonts, reminders…) stay per device.
- First sign-in with data on both sides: *Combine*, *Use my account's data*, or
  *Use this device's data* (the other devices then switch to it on their next sync).
- The session (refresh token) is stored in the app's private folder; on Windows it is also
  encrypted with Windows DPAPI.
- **Delete account** removes the account and all of its cloud data.

## Free plan limits (Spark)

Firestore: 1 GiB stored, 50,000 document reads and 20,000 writes per day for the whole
project. A typical user's library is a few MB, and an idle sync costs one read, so this is
plenty for you and a group of friends.
