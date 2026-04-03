# Sunzzari

Private iOS app for Elisa and Cathy. Built with SwiftUI, Notion API, and Cloudinary.

---

## Workflow: Cathy edits, Elisa installs

### Setup (one time)

1. Clone the repo:
   ```bash
   git clone https://github.com/elisafazz/sunzzari-app.git
   cd sunzzari-app
   ```
2. Open `Sunzzari.xcodeproj` in Xcode
3. All credentials are already in `Sunzzari/Config/Constants.swift` — no extra setup needed

### Making changes

1. Pull latest before starting:
   ```bash
   git pull origin main
   ```
2. Make your changes in Xcode or with Claude Code
3. Build and test on your simulator or device (Cmd+R in Xcode)
4. Commit and push:
   ```bash
   git add .
   git commit -m "describe what you changed"
   git push origin main
   ```

### Installing on Cathy's phone (Elisa's job)

1. Pull latest:
   ```bash
   git pull origin main
   ```
2. Open `Sunzzari.xcodeproj` in Xcode
3. Plug in Cathy's phone, select it as the build target
4. Hit Cmd+R — Xcode builds and installs directly

---

## Project structure

```
Sunzzari/
├── Config/
│   ├── Constants.swift        — all tokens and DB IDs
│   └── AppColors.swift        — color palette
├── Models/                    — data models (DinosaurPhoto, Memory, BestOfEntry, etc.)
├── Services/
│   ├── NotionService.swift    — all Notion API calls
│   ├── CloudinaryService.swift
│   └── NotificationService.swift
└── Views/
    ├── Today/                 — landing tab (today's memories or Best Of fallback)
    ├── Gallery/               — dinosaur photo gallery
    ├── BestOf/                — best of entries by year
    ├── OnThisDay/             — memories
    ├── Search/                — universal search
    ├── Travel/                — travel map link
    ├── Info/                  — reference info from Notion
    └── Shared/                — reusable components
```

## Stack

- SwiftUI, iOS 17+
- Notion API (direct HTTP, embedded token)
- Cloudinary (unsigned upload, CDN delivery)
- iOS Local Notifications
- No backend, no auth

## Credentials

All in `Sunzzari/Config/Constants.swift`. This repo is private — do not make it public.
