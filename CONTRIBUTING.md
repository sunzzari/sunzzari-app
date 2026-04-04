# How to Edit the Sunzzari App

Once you make changes and push to GitHub, Xcode Cloud automatically builds and delivers the update to both phones via TestFlight. No USB or manual steps needed.

---

## Prerequisites

- Mac with Xcode installed (free from the Mac App Store)
- Access to the GitHub repo: `https://github.com/elisafazz/sunzzari-app`
- Git installed (comes with Xcode Command Line Tools)

---

## First-Time Setup

Clone the repo to your Mac:

```bash
git clone https://github.com/elisafazz/sunzzari-app.git
cd sunzzari-app
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

That's it. Xcode Cloud picks up the push, builds the app (~10-15 min), and TestFlight delivers it to both phones automatically. You'll get a notification on both phones to tap "Update."

---

## Monitoring the Build

In Xcode: Report Navigator (the flag icon in the left toolbar) → Cloud tab shows build progress.

In browser: appstoreconnect.apple.com → Xcode Cloud → Builds

---

## Content Changes (no code needed)

Most content in the app comes directly from Notion. To add or edit:

- **Best Of entries** — go to the Sunzzari Best Of database in Notion
- **Memories** — go to the Sunzzari Memories database in Notion
- **Dinosaur photos** — use the Gallery tab in the app (bulk import or add one at a time)

No push required for Notion changes — the app fetches live data.

---

## Key Files

| File | What it controls |
|------|-----------------|
| `Sunzzari/Config/Constants.swift` | API tokens, database IDs |
| `Sunzzari/Config/AppColors.swift` | Color palette |
| `Sunzzari/ContentView.swift` | Tab structure |
| `Sunzzari/Views/Today/TodayView.swift` | Today tab |
| `Sunzzari/Views/BestOf/BestOfView.swift` | Best Of tab |
| `Sunzzari/Views/Gallery/GalleryView.swift` | Gallery tab |
| `Sunzzari/Views/Hub/HubView.swift` | Hub tab (restaurants, wine, activities) |
