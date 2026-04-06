# How to Edit the Sunzzari App

This guide covers everything needed to make changes to the app and get them onto both phones.

---

## Who Can Do What

| Task | Elisa | Cathy |
|------|-------|-------|
| Edit code and push to GitHub | Yes | Yes (needs Mac + Xcode) |
| Trigger Xcode Cloud build | Yes (Apple Developer account) | No — but pushing to GitHub triggers it automatically |
| Monitor build in App Store Connect | Yes | No |
| Receive TestFlight update on phone | Yes | Yes |
| Add Notion content (no code) | Yes | Yes |

Xcode Cloud is tied to Elisa's Apple Developer account. Anyone can push code to GitHub — the build and TestFlight delivery happen automatically.

---

## Two Repos — Know Which One to Edit

| Repo | URL | What it controls | Auto-deploy |
|------|-----|-----------------|-------------|
| **sunzzari-app** | github.com/sunzzari/sunzzari-app | iOS app (all Swift/UI code) | Xcode Cloud → TestFlight |
| **sunzzari-backend** | github.com/sunzzari/sunzzari-backend | Push notification server (APNs endpoint) | Vercel auto-deploy |

**99% of the time you want `sunzzari-app`.** The backend is only touched if the push notification server itself needs changes (rare).

There is a `backend/` subfolder inside `sunzzari-app` — this is a stale copy and is not deployed anywhere. Ignore it.

---

## First-Time Setup (one time per machine)

**Requirements**: Mac with Xcode (free from Mac App Store) and Git.

Clone the repo:

```bash
git clone https://github.com/sunzzari/sunzzari-app.git
cd sunzzari-app
```

Create your local secrets file (required to build — this file is gitignored and never committed to GitHub):

```bash
cp Sunzzari/Config/Secrets.template Sunzzari/Config/Secrets.swift
```

Open `Sunzzari/Config/Secrets.swift` and replace the two placeholder values with the real ones. Ask Elisa for the values if you don't have them.

Open the project in Xcode:

```bash
open Sunzzari.xcodeproj
```

---

## Making a Code Change

1. Pull the latest code first:
   ```bash
   git pull
   ```
2. Open `Sunzzari.xcodeproj` in Xcode
3. Edit the Swift files under `Sunzzari/`
4. Test on your phone:
   - Connect your iPhone via USB
   - Select your device in the Xcode toolbar (top center)
   - Press Cmd+R to build and run directly on your phone

---

## Pushing the Update to Both Phones

Once the change looks good:

```bash
git add -A
git commit -m "describe what you changed"
git push
```

That's it. Xcode Cloud picks up the push automatically and does the rest:

1. Builds the app (~10-15 min)
2. Submits to TestFlight
3. Both phones receive a notification: "New version available — tap to update"

**You do not need to do anything in TestFlight or App Store Connect.** It is fully automatic.

---

## Monitoring the Build (Elisa only)

After pushing, you can watch the build at:

- **Browser**: appstoreconnect.apple.com → Apps → Sunzzari → Xcode Cloud → Builds
- **Xcode**: Report Navigator (Cmd+9) → Cloud tab

A spinning circle means it's building. A green checkmark means TestFlight delivery is in progress. A red X means something failed — open the build to see the errors.

---

## If the Build Fails

1. Open the failed build in App Store Connect → click "Archive - iOS" → read the errors
2. Fix the issue in the code, commit, and push again
3. Xcode Cloud will automatically start a new build

---

## Content Changes (no code, no push needed)

Most app content comes live from Notion — no code push required:

- **Best Of entries** — edit in the Sunzzari Best Of Notion database
- **Memories** — edit in the Sunzzari Memories Notion database
- **Dinosaur photos** — use the Gallery tab in the app (bulk import or add one at a time)

---

## Key Files

| File | What it controls |
|------|-----------------|
| `Sunzzari/Config/Secrets.swift` | API tokens — gitignored, never commit |
| `Sunzzari/Config/Constants.swift` | Database IDs and non-secret config |
| `Sunzzari/Config/AppColors.swift` | Color palette |
| `Sunzzari/ContentView.swift` | Tab structure |
| `Sunzzari/Views/Today/TodayView.swift` | Today tab |
| `Sunzzari/Views/BestOf/BestOfView.swift` | Best Of tab |
| `Sunzzari/Views/Gallery/GalleryView.swift` | Gallery tab |
| `Sunzzari/Views/Hub/HubView.swift` | Hub tab (restaurants, wine, activities) |
| `ci_scripts/ci_post_clone.sh` | Xcode Cloud setup script — generates Secrets.swift from env vars |

---

## Important: Never Commit Secrets.swift

`Secrets.swift` is gitignored. Never force-add it. If the Notion API key ever needs to be rotated:

1. Get a new token from notion.so/my-integrations
2. Update `Secrets.swift` locally
3. Update the `NOTION_TOKEN` env var in App Store Connect → Xcode Cloud → Workflow → Environment
4. Push any commit to trigger a new build
