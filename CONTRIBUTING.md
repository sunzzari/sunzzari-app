# How to Edit the Sunzzari App

---

## Two Repos — Know Which One to Edit

| Repo | URL | What it controls | Auto-deploy |
|------|-----|-----------------|-------------|
| **sunzzari-app** | github.com/sunzzari/sunzzari-app | iOS app (all Swift/UI code) | Xcode Cloud → TestFlight |
| **sunzzari-backend** | github.com/sunzzari/sunzzari-backend | Push notification server (APNs endpoint) | Vercel auto-deploy |

**99% of the time you want `sunzzari-app`.** The backend is only touched if the push notification server itself needs changes (rare).

Note: there is a `backend/` subfolder inside `sunzzari-app` — this is a stale copy and is not deployed anywhere. Ignore it. All real backend changes go in `sunzzari-backend`.

Both repos are public (required for Vercel on a free org plan).

---

## Prerequisites (for app changes)

- Mac with Xcode installed (free from the Mac App Store)
- Git installed (comes with Xcode Command Line Tools)
- Access to: `https://github.com/sunzzari/sunzzari-app`

---

## First-Time Setup

Clone the app repo:

```bash
git clone https://github.com/sunzzari/sunzzari-app.git
cd sunzzari-app
```

If you already cloned the old repo (`elisafazz/sunzzari-app`), update your remote:

```bash
git remote set-url origin https://github.com/sunzzari/sunzzari-app.git
```

Open the project in Xcode:

```bash
open Sunzzari.xcodeproj
```

---

## Making Changes

1. Open `Sunzzari.xcodeproj` in Xcode
2. Make your edits in the source files (Swift files are under the `Sunzzari/` folder)
3. To preview your changes on a device:
   - Connect your iPhone via USB
   - Select your device in the toolbar (top center of Xcode)
   - Press the Play button (or Cmd+R) to build and run

---

## Pushing an Update to Both Phones

Once your changes look good, push to GitHub:

```bash
git add -A
git commit -m "describe what you changed"
git push
```

Xcode Cloud picks up the push, builds the app (~10-15 min), and TestFlight delivers it to both phones automatically. You'll get a notification to tap "Update."

---

## Monitoring the Build

In Xcode: Report Navigator (flag icon in left toolbar) → Cloud tab.

In browser: appstoreconnect.apple.com → Xcode Cloud → Builds

---

## Content Changes (no code needed)

Most content comes directly from Notion:

- **Best Of entries** — Sunzzari Best Of database in Notion
- **Memories** — Sunzzari Memories database in Notion
- **Dinosaur photos** — Gallery tab in the app (bulk import or add one at a time)

No push required for Notion changes — the app fetches live data.

---

## Key Files (sunzzari-app)

| File | What it controls |
|------|-----------------|
| `Sunzzari/Config/Constants.swift` | API tokens, database IDs |
| `Sunzzari/Config/AppColors.swift` | Color palette |
| `Sunzzari/ContentView.swift` | Tab structure |
| `Sunzzari/Views/Today/TodayView.swift` | Today tab |
| `Sunzzari/Views/BestOf/BestOfView.swift` | Best Of tab |
| `Sunzzari/Views/Gallery/GalleryView.swift` | Gallery tab |
| `Sunzzari/Views/Hub/HubView.swift` | Hub tab (restaurants, wine, activities) |
