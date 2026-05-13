# Changelog

## 2026-05-13

### Stories overhaul

- **New Today header story ring (IG-style).** When the partner has active
  stories, a colored avatar ring appears in the Today page header next to the
  inbox bell. Solid accent ring when there are unseen stories, faded grey once
  everything has been watched. Tap opens the fullscreen story tray.
- **Stories tab is now a pure compose launcher.** Tapping the Stories tab
  always opens the new-story flow directly; viewing partner stories happens
  from the Today header. Returns to Today after post or cancel.
- **Stories Archive moved to More.** New "Stories Archive" row in the More
  tab navigates to all past archived stories. The old in-tab archive button
  is gone.
- **Instagram-style compose (full rewrite).** Fullscreen photo, tap the photo
  to write a caption inline with keyboard, drag the caption pill to position,
  floating "Aa" button to re-edit. Location field removed.
- **Camera defaults to flash off.** `cameraFlashMode = .off` on capture.
- **No more flash-of-compose-step before camera.** The picker placeholder
  stays hidden behind the camera slide-up; reveals only if the camera was
  cancelled or unavailable.
- **Replay screen no longer blacks out the last frame.** Replaced the
  full-screen dim and giant Replay circle with a small glass-blur Replay pill
  + minimal Close. The final story photo stays fully visible behind.
- **Notifications now count UNSEEN stories instead of total daily count.**
  New `SeenStoriesStore` tracks viewed story IDs locally. Inbox titles read
  "Elisa posted 3 stories" only for stories you haven't watched yet, and
  auto-mark the entry read when the bucket is fully viewed.

### Build / project

- **Restricted supported platforms to iOS only** (`iphoneos`,
  `iphonesimulator`). Previously included `macosx`, `xros`, and `xrsimulator`,
  which made Xcode previews fail with a UIKit-not-found error in
  AnthropicService and Mac App provisioning errors. Previews now build.
- `SDKROOT` pinned to `iphoneos`, `TARGETED_DEVICE_FAMILY` reduced to `1,2`
  (iPhone + iPad), `XROS_DEPLOYMENT_TARGET` removed.
