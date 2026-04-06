# How to Update the Sunzzari App

Complete reference — from making a code change to both phones receiving the update.

---

## Overview: How Updates Work

```
Edit code → git push → Xcode Cloud builds (~10-15 min) → Archive succeeds
→ Clear compliance in App Store Connect → Add build to Sunzzari Group
→ Both phones get TestFlight notification → Tap Update
```

**Nothing is fully automatic.** After each successful build, two manual steps in App Store Connect are required before the update reaches the phones.

---

## Who Can Do What

| Task | Elisa | Cathy |
|------|-------|-------|
| Edit code and push to GitHub | Yes | Yes (needs Mac + Xcode) |
| Monitor build in App Store Connect | Yes (Apple Developer account) | No |
| Clear compliance + add build to group | Yes | No |
| Receive TestFlight update on phone | Yes | Yes |
| Add/edit Notion content (no code) | Yes | Yes |

---

## Part 1 — First-Time Setup (once per machine)

**Requirements**: Mac with Xcode (free from Mac App Store) and Git.

**1. Clone the repo**
```bash
git clone https://github.com/sunzzari/sunzzari-app.git
cd sunzzari-app
```

**2. Create your local secrets file** (required to build — gitignored, never committed)
```bash
cp Sunzzari/Config/Secrets.template Sunzzari/Config/Secrets.swift
```
Open `Sunzzari/Config/Secrets.swift` and replace the two placeholder values with the real tokens. Ask Elisa if you don't have them.

**3. Open in Xcode**
```bash
open Sunzzari.xcodeproj
```

---

## Part 2 — Making a Code Change

**1. Pull latest before editing**
```bash
git pull
```

**2. Edit files in Xcode**
All Swift source files are under `Sunzzari/`. Key files:

| File | What it controls |
|------|-----------------|
| `Sunzzari/Config/Secrets.swift` | API tokens — gitignored, NEVER commit |
| `Sunzzari/Config/Constants.swift` | Database IDs and non-secret config |
| `Sunzzari/Config/AppColors.swift` | Color palette |
| `Sunzzari/ContentView.swift` | Tab structure |
| `Sunzzari/Views/Today/TodayView.swift` | Today tab |
| `Sunzzari/Views/BestOf/BestOfView.swift` | Best Of tab |
| `Sunzzari/Views/Gallery/GalleryView.swift` | Gallery tab |
| `Sunzzari/Views/Hub/HubView.swift` | Hub tab (restaurants, wine, activities) |
| `ci_scripts/ci_post_clone.sh` | Xcode Cloud setup script — do not edit |

**3. Test on device before pushing**
- Connect iPhone via USB
- Select your device in the Xcode toolbar (top center)
- Press Cmd+R to build and run directly on your phone

**4. Push to GitHub**
```bash
git add -A
git commit -m "describe what you changed"
git push
```

---

## Part 3 — Monitoring the Build

After pushing, Xcode Cloud automatically starts a build. Monitor at:

**App Store Connect → Xcode Cloud → Builds**

Build stages:
1. **Post-Clone** — generates `Secrets.swift` from environment variables
2. **Archive - iOS** — compiles and archives the app (~10-15 min)
3. **TestFlight Internal Testing - iOS** — uploads the archive

**If the progress bar shows ~46% and appears stuck**: this is a display bug. Check the TestFlight tab instead — the build has likely already completed there.

**If Archive - iOS shows red (failed)**: click into it to see the errors. Fix the code, push again, and a new build starts automatically.

---

## Part 4 — Delivering the Build to Both Phones

After Archive - iOS succeeds, one manual step is required.

### Add Build to Tester Group

App Store Connect → **TestFlight** tab → **Sunzzari Group** → **Builds** tab → **+** → select the new build → **Add**

Both phones (Elisa + Cathy) will receive a TestFlight notification within a few minutes. Tap **Update** in the TestFlight app.

> Note: "Missing Compliance" warnings are no longer expected — `ITSAppUsesNonExemptEncryption` is set in Info.plist. If you see it anyway, go to TestFlight → Builds → iOS → Manage Compliance → Yes, Exempt.

---

## Part 5 — Content Changes (no code needed)

Most app content is fetched live from Notion — no code push required:

- **Best Of entries** — edit in the Sunzzari Best Of Notion database
- **Memories** — edit in the Sunzzari Memories Notion database
- **Dinosaur photos** — use the Gallery tab in the app (bulk import or one at a time)

---

## Part 6 — Rotating the Notion API Key

If the Notion token is ever revoked or needs to be rotated:

1. Go to notion.so/my-integrations → Sunzzari integration → generate a new token
2. Update `Sunzzari/Config/Secrets.swift` locally with the new token
3. Update the `NOTION_TOKEN` environment variable in App Store Connect → Xcode Cloud → Manage Workflows → TestFlight Release → Environment
4. Push any commit to trigger a new build

---

## Two Repos — Know Which One to Edit

| Repo | URL | Purpose | Auto-deploy |
|------|-----|---------|-------------|
| **sunzzari-app** | github.com/sunzzari/sunzzari-app | iOS app (all Swift/UI code) | Xcode Cloud → TestFlight |
| **sunzzari-backend** | github.com/sunzzari/sunzzari-backend | Push notification server | Vercel auto-deploy |

99% of changes go in `sunzzari-app`. The backend is only touched if the push notification server needs changes (rare).

There is a `backend/` subfolder inside `sunzzari-app` — this is a stale copy, not deployed anywhere. Ignore it.

---

## Never Commit Secrets.swift

`Secrets.swift` is gitignored. Never force-add it to git. The file is generated automatically during Xcode Cloud builds via `ci_scripts/ci_post_clone.sh` using environment variables stored in App Store Connect.
